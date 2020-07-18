terraform {
  required_version = "~> 0.12"
}

locals {
  lambda_api_arn              = var.lambda_api_qualifier == null ? aws_lambda_function.api.arn : "${aws_lambda_function.api.arn}:${var.lambda_api_qualifier}"
  lambda_reindex_arn          = var.lambda_reindex_qualifier == null ? aws_lambda_function.reindex.arn : "${aws_lambda_function.reindex.arn}:${var.lambda_reindex_qualifier}"
  log_group_retention_in_days = var.log_group_retention_in_days
  tags                        = var.tags

  iam_role = {
    description = var.iam_role_description
    name        = var.iam_role_name
    policy_name = var.iam_role_policy_name
  }

  lambda_api = {
    description        = var.lambda_api_description
    function_name      = var.lambda_api_function_name
    memory_size        = var.lambda_api_memory_size
    publish            = var.lambda_api_publish
    qualifier          = var.lambda_api_qualifier
    fallback_index_url = var.lambda_api_fallback_index_url
    runtime            = var.lambda_runtime
  }

  lambda_reindex = {
    description   = var.lambda_reindex_description
    function_name = var.lambda_reindex_function_name
    memory_size   = var.lambda_reindex_memory_size
    publish       = var.lambda_reindex_publish
    qualifier     = var.lambda_reindex_qualifier
    runtime       = var.lambda_runtime
  }

  rest_api = {
    authorization    = var.rest_api_authorization
    authorizer_id    = var.rest_api_authorizer_id
    base_path        = var.rest_api_base_path
    execution_arn    = var.rest_api_execution_arn
    id               = var.rest_api_id
    root_resource_id = var.rest_api_root_resource_id
  }

  s3 = {
    bucket_name       = var.s3_bucket_name
    presigned_url_ttl = var.s3_presigned_url_ttl
  }
}

# S3

resource aws_s3_bucket pypi {
  acl    = "private"
  bucket = local.s3.bucket_name
  tags   = local.tags
}

resource aws_s3_bucket_notification reindex {
  bucket = aws_s3_bucket.pypi.id

  lambda_function {
    filter_suffix       = ".tar.gz"
    id                  = "InvokeReindexer"
    lambda_function_arn = local.lambda_reindex_arn

    events = [
      "s3:ObjectCreated:*",
      "s3:ObjectRemoved:*",
    ]
  }
}

resource aws_s3_bucket_public_access_block pypi {
  block_public_acls       = true
  block_public_policy     = true
  bucket                  = aws_s3_bucket.pypi.id
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM ROLE

data aws_iam_policy_document assume_role {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data aws_iam_policy_document policy {
  statement {
    sid = "ReadS3"

    actions = [
      "s3:Get*",
      "s3:List*",
    ]

    resources = [
      "arn:aws:s3:::${aws_s3_bucket.pypi.bucket}",
      "arn:aws:s3:::${aws_s3_bucket.pypi.bucket}/*",
    ]
  }

  statement {
    sid       = "Reindex"
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${aws_s3_bucket.pypi.bucket}/index.html"]
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

resource aws_iam_role role {
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  description        = local.iam_role.description
  name               = local.iam_role.name
  tags               = local.tags
}

resource aws_iam_role_policy policy {
  name   = local.iam_role.policy_name
  role   = aws_iam_role.role.id
  policy = data.aws_iam_policy_document.policy.json
}

# LAMBDA

data archive_file package {
  source_file = "${path.module}/index.py"
  output_path = "${path.module}/package.zip"
  type        = "zip"
}

# LAMBDA :: API PROXY

resource aws_cloudwatch_log_group api {
  name              = "/aws/lambda/${aws_lambda_function.api.function_name}"
  retention_in_days = local.log_group_retention_in_days
  tags              = local.tags
}

resource aws_lambda_function api {
  description      = local.lambda_api.description
  filename         = data.archive_file.package.output_path
  function_name    = local.lambda_api.function_name
  handler          = "index.proxy_request"
  memory_size      = local.lambda_api.memory_size
  publish          = local.lambda_api.publish
  role             = aws_iam_role.role.arn
  runtime          = local.lambda_api.runtime
  source_code_hash = data.archive_file.package.output_base64sha256
  tags             = local.tags

  environment {
    variables = {
      BASE_PATH            = local.rest_api.base_path
      FALLBACK_INDEX_URL   = local.lambda_api.fallback_index_url
      S3_BUCKET            = aws_s3_bucket.pypi.bucket
      S3_PRESIGNED_URL_TTL = local.s3.presigned_url_ttl
    }
  }
}

resource aws_lambda_permission invoke_api {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  qualifier     = local.lambda_api.qualifier
  statement_id  = "InvokeAPI"
  source_arn    = "${local.rest_api.execution_arn}/*/*/*"
}

# LAMBDA :: REINDEXER

resource aws_cloudwatch_log_group reindex {
  name              = "/aws/lambda/${aws_lambda_function.reindex.function_name}"
  retention_in_days = local.log_group_retention_in_days
  tags              = local.tags
}

resource aws_lambda_function reindex {
  description      = local.lambda_reindex.description
  filename         = data.archive_file.package.output_path
  function_name    = local.lambda_reindex.function_name
  handler          = "index.reindex_bucket"
  memory_size      = local.lambda_reindex.memory_size
  publish          = local.lambda_reindex.publish
  role             = aws_iam_role.role.arn
  runtime          = local.lambda_reindex.runtime
  source_code_hash = data.archive_file.package.output_base64sha256
  tags             = local.tags

  environment {
    variables = {
      S3_BUCKET = aws_s3_bucket.pypi.bucket
    }
  }
}

resource aws_lambda_permission invoke_reindex {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.reindex.function_name
  principal     = "s3.amazonaws.com"
  qualifier     = local.lambda_reindex.qualifier
  statement_id  = "InvokeReindexer"
  source_arn    = aws_s3_bucket.pypi.arn
}

# API GATEWAY :: /

resource aws_api_gateway_method root_get {
  authorization = local.rest_api.authorization
  authorizer_id = local.rest_api.authorizer_id
  http_method   = "GET"
  resource_id   = local.rest_api.root_resource_id
  rest_api_id   = local.rest_api.id
}

resource aws_api_gateway_method root_head {
  authorization = local.rest_api.authorization
  authorizer_id = local.rest_api.authorizer_id
  http_method   = "HEAD"
  resource_id   = local.rest_api.root_resource_id
  rest_api_id   = local.rest_api.id
}

resource aws_api_gateway_method root_post {
  authorization = local.rest_api.authorization
  authorizer_id = local.rest_api.authorizer_id
  http_method   = "POST"
  resource_id   = local.rest_api.root_resource_id
  rest_api_id   = local.rest_api.id
}

resource aws_api_gateway_integration root_get {
  content_handling        = "CONVERT_TO_TEXT"
  http_method             = aws_api_gateway_method.root_get.http_method
  integration_http_method = "POST"
  resource_id             = local.rest_api.root_resource_id
  rest_api_id             = local.rest_api.id
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api.invoke_arn
}

resource aws_api_gateway_integration root_head {
  content_handling        = "CONVERT_TO_TEXT"
  http_method             = aws_api_gateway_method.root_head.http_method
  integration_http_method = "POST"
  resource_id             = local.rest_api.root_resource_id
  rest_api_id             = local.rest_api.id
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api.invoke_arn
}

resource aws_api_gateway_integration root_post {
  content_handling        = "CONVERT_TO_TEXT"
  http_method             = aws_api_gateway_method.root_post.http_method
  integration_http_method = "POST"
  resource_id             = local.rest_api.root_resource_id
  rest_api_id             = local.rest_api.id
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api.invoke_arn
}

# API GATEWAY :: /{proxy+}

resource aws_api_gateway_resource proxy {
  rest_api_id = local.rest_api.id
  parent_id   = local.rest_api.root_resource_id
  path_part   = "{proxy+}"
}

resource aws_api_gateway_method proxy_get {
  authorization = local.rest_api.authorization
  authorizer_id = local.rest_api.authorizer_id
  http_method   = "GET"
  resource_id   = aws_api_gateway_resource.proxy.id
  rest_api_id   = local.rest_api.id
}

resource aws_api_gateway_method proxy_head {
  authorization = local.rest_api.authorization
  authorizer_id = local.rest_api.authorizer_id
  http_method   = "HEAD"
  resource_id   = aws_api_gateway_resource.proxy.id
  rest_api_id   = local.rest_api.id
}

resource aws_api_gateway_method proxy_post {
  authorization = local.rest_api.authorization
  authorizer_id = local.rest_api.authorizer_id
  http_method   = "POST"
  resource_id   = aws_api_gateway_resource.proxy.id
  rest_api_id   = local.rest_api.id
}

resource aws_api_gateway_integration proxy_get {
  content_handling        = "CONVERT_TO_TEXT"
  http_method             = aws_api_gateway_method.proxy_get.http_method
  integration_http_method = "POST"
  resource_id             = aws_api_gateway_resource.proxy.id
  rest_api_id             = local.rest_api.id
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api.invoke_arn
}

resource aws_api_gateway_integration proxy_head {
  content_handling        = "CONVERT_TO_TEXT"
  http_method             = aws_api_gateway_method.proxy_head.http_method
  integration_http_method = "POST"
  resource_id             = aws_api_gateway_resource.proxy.id
  rest_api_id             = local.rest_api.id
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api.invoke_arn
}

resource aws_api_gateway_integration proxy_post {
  content_handling        = "CONVERT_TO_TEXT"
  http_method             = aws_api_gateway_method.proxy_post.http_method
  integration_http_method = "POST"
  resource_id             = aws_api_gateway_resource.proxy.id
  rest_api_id             = local.rest_api.id
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api.invoke_arn
}
