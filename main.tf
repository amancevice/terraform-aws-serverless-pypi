#################
#   TERRAFORM   #
#################

terraform {
  required_version = "~> 1.0"

  required_providers {
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }

    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

##############
#   LOCALS   #
##############

locals {
  event_rule = {
    description = var.event_rule_description
    name        = var.event_rule_name
  }

  iam_role = {
    description = var.iam_role_description
    name        = var.iam_role_name
    policy_name = var.iam_role_policy_name
    tags        = var.iam_role_tags
  }

  lambda = {
    filename         = data.archive_file.package.output_path
    runtime          = var.lambda_runtime
    source_code_hash = data.archive_file.package.output_base64sha256
  }

  lambda_api = {
    description        = var.lambda_api_description
    function_name      = var.lambda_api_function_name
    memory_size        = var.lambda_api_memory_size
    fallback_index_url = var.lambda_api_fallback_index_url
    tags               = var.lambda_api_tags
    timeout            = var.lambda_api_timeout
  }

  lambda_reindex = {
    description   = var.lambda_reindex_description
    function_name = var.lambda_reindex_function_name
    memory_size   = var.lambda_reindex_memory_size
    tags          = var.lambda_reindex_tags
    timeout       = var.lambda_reindex_timeout
  }

  log_group_api = {
    retention_in_days = var.log_group_api_retention_in_days
    tags              = var.log_group_api_tags
  }

  log_group_reindex = {
    retention_in_days = var.log_group_reindex_retention_in_days
    tags              = var.log_group_reindex_tags
  }

  rest_api = {
    authorization_type = var.api_authorization_type
    authorizer_id      = var.api_authorizer_id
    execution_arn      = var.api_execution_arn
    id                 = var.api_id
    root_resource_id   = var.api_root_resource_id
  }

  routes = {
    "GET /"            = { http_method : "GET", resource_id : local.rest_api.root_resource_id }
    "HEAD /"           = { http_method : "HEAD", resource_id : local.rest_api.root_resource_id }
    "POST /"           = { http_method : "POST", resource_id : local.rest_api.root_resource_id }
    "GET /{package+}"  = { http_method : "GET", resource_id : aws_api_gateway_resource.proxy.id }
    "HEAD /{package+}" = { http_method : "HEAD", resource_id : aws_api_gateway_resource.proxy.id }
  }

  s3 = {
    bucket_name       = var.s3_bucket_name
    bucket_tags       = var.s3_bucket_tags
    presigned_url_ttl = var.s3_presigned_url_ttl
  }
}

####################
#   S3 :: BUCKET   #
####################

resource "aws_s3_bucket" "pypi" {
  bucket = local.s3.bucket_name
  tags   = local.s3.bucket_tags
}

resource "aws_s3_bucket_acl" "pypi" {
  bucket = aws_s3_bucket.pypi.id
  acl    = "private"
}

resource "aws_s3_bucket_public_access_block" "pypi" {
  block_public_acls       = true
  block_public_policy     = true
  bucket                  = aws_s3_bucket.pypi.id
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "index" {
  bucket  = aws_s3_bucket.pypi.id
  key     = "index.html"
  content = <<-EOT
    <!DOCTYPE html>
    <html>

    <head>
      <meta name="pypi:repository-version" content="1.0">
      <title>Simple index</title>
    </head>

    <body>
      <h1>Simple index</h1>
    </body>

    </html>
  EOT

  lifecycle { ignore_changes = [content] }
}

####################
#   S3 :: EVENTS   #
####################

data "aws_caller_identity" "current" {
}

resource "aws_s3_bucket_notification" "reindex" {
  bucket      = aws_s3_bucket.pypi.id
  eventbridge = true
}

###################
#   EVENTBRIDGE   #
###################

resource "aws_cloudwatch_event_rule" "reindex" {
  description = local.event_rule.description
  name        = local.event_rule.name

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created", "Object Deleted"]

    detail = {
      bucket = { name = [aws_s3_bucket.pypi.id] }
      object = { key = [{ anything-but = ["index.html"] }] }
    }
  })
}

resource "aws_cloudwatch_event_target" "reindex" {
  arn        = aws_lambda_function.reindex.arn
  input_path = "$.detail"
  rule       = aws_cloudwatch_event_rule.reindex.name
  target_id  = "reindex"
}

###########
#   IAM   #
###########

data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "policy" {
  statement {
    sid       = "ListBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.pypi.arn]
  }

  statement {
    sid       = "GetObjects"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.pypi.arn}/*"]
  }

  statement {
    sid       = "PutIndex"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.pypi.arn}/index.html"]
  }

  statement {
    sid       = "WriteLambdaLogs"
    resources = ["*"]

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
  }
}

resource "aws_iam_role" "role" {
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  description        = local.iam_role.description
  name               = local.iam_role.name
  tags               = local.iam_role.tags

  inline_policy {
    name   = local.iam_role.policy_name
    policy = data.aws_iam_policy_document.policy.json
  }
}

#########################
#   LAMBDA :: PACKAGE   #
#########################

data "archive_file" "package" {
  source_file = "${path.module}/python/index.py"
  output_path = "${path.module}/python/package.zip"
  type        = "zip"
}

###########################
#   LAMBDA :: API PROXY   #
###########################

resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/lambda/${aws_lambda_function.api.function_name}"
  retention_in_days = local.log_group_api.retention_in_days
  tags              = local.log_group_api.tags
}

resource "aws_lambda_function" "api" {
  architectures    = ["arm64"]
  description      = local.lambda_api.description
  filename         = local.lambda.filename
  function_name    = local.lambda_api.function_name
  handler          = "index.proxy_request"
  memory_size      = local.lambda_api.memory_size
  role             = aws_iam_role.role.arn
  runtime          = local.lambda.runtime
  source_code_hash = local.lambda.source_code_hash
  tags             = local.lambda_api.tags
  timeout          = local.lambda_api.timeout

  environment {
    variables = {
      FALLBACK_INDEX_URL   = local.lambda_api.fallback_index_url
      S3_BUCKET            = aws_s3_bucket.pypi.bucket
      S3_PRESIGNED_URL_TTL = local.s3.presigned_url_ttl
    }
  }
}

resource "aws_lambda_permission" "api" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${local.rest_api.execution_arn}/*/*/*"
}

###########################
#   LAMBDA :: REINDEXER   #
###########################

resource "aws_cloudwatch_log_group" "reindex" {
  name              = "/aws/lambda/${aws_lambda_function.reindex.function_name}"
  retention_in_days = local.log_group_reindex.retention_in_days
  tags              = local.log_group_reindex.tags
}

resource "aws_lambda_function" "reindex" {
  architectures    = ["arm64"]
  description      = local.lambda_reindex.description
  filename         = local.lambda.filename
  function_name    = local.lambda_reindex.function_name
  handler          = "index.reindex_bucket"
  memory_size      = local.lambda_reindex.memory_size
  role             = aws_iam_role.role.arn
  runtime          = local.lambda.runtime
  source_code_hash = local.lambda.source_code_hash
  tags             = local.lambda_reindex.tags
  timeout          = local.lambda_reindex.timeout

  environment {
    variables = {
      S3_BUCKET = aws_s3_bucket.pypi.bucket
    }
  }
}

resource "aws_lambda_permission" "reindex" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.reindex.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.reindex.arn
}

###########################
#   API GATEWAY :: REST   #
###########################

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = local.rest_api.id
  parent_id   = local.rest_api.root_resource_id
  path_part   = "{package+}"
}

resource "aws_api_gateway_method" "methods" {
  for_each      = local.routes
  authorization = local.rest_api.authorization_type
  authorizer_id = local.rest_api.authorizer_id
  http_method   = each.value.http_method
  resource_id   = each.value.resource_id
  rest_api_id   = local.rest_api.id
}

resource "aws_api_gateway_integration" "integrations" {
  depends_on              = [aws_api_gateway_method.methods]
  for_each                = local.routes
  rest_api_id             = local.rest_api.id
  resource_id             = each.value.resource_id
  http_method             = each.value.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api.invoke_arn
}
