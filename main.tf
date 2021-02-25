terraform {
  required_version = "~> 0.13"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

locals {
  http_api = {
    id            = var.http_api_id
    execution_arn = var.http_api_execution_arn
  }

  iam_role = {
    description = var.iam_role_description
    name        = var.iam_role_name
    policy_name = var.iam_role_policy_name
    tags        = var.iam_role_tags
  }

  lambda = {
    filename         = "${path.module}/package.zip"
    runtime          = var.lambda_runtime
    source_code_hash = filebase64sha256("${path.module}/package.zip")
  }

  lambda_api = {
    alias_name             = var.lambda_api_alias_name
    alias_function_version = var.lambda_api_alias_function_version
    description            = var.lambda_api_description
    function_name          = var.lambda_api_function_name
    memory_size            = var.lambda_api_memory_size
    publish                = var.lambda_api_publish
    fallback_index_url     = var.lambda_api_fallback_index_url
    tags                   = var.lambda_api_tags
  }

  lambda_reindex = {
    alias_name             = var.lambda_reindex_alias_name
    alias_function_version = var.lambda_reindex_alias_function_version
    description            = var.lambda_reindex_description
    function_name          = var.lambda_reindex_function_name
    memory_size            = var.lambda_reindex_memory_size
    publish                = var.lambda_reindex_publish
    tags                   = var.lambda_reindex_tags
  }

  log_group_api = {
    retention_in_days = var.log_group_api_retention_in_days
    tags              = var.log_group_api_tags
  }

  log_group_reindex = {
    retention_in_days = var.log_group_reindex_retention_in_days
    tags              = var.log_group_reindex_tags
  }

  s3 = {
    bucket_name       = var.s3_bucket_name
    bucket_tags       = var.s3_bucket_tags
    presigned_url_ttl = var.s3_presigned_url_ttl
  }

  sns_topic = {
    name = var.sns_topic_name
    tags = var.sns_topic_tags
  }
}

# S3 :: BUCKET

resource "aws_s3_bucket" "pypi" {
  acl    = "private"
  bucket = local.s3.bucket_name
  tags   = local.s3.bucket_tags
}

resource "aws_s3_bucket_public_access_block" "pypi" {
  block_public_acls       = true
  block_public_policy     = true
  bucket                  = aws_s3_bucket.pypi.id
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 :: EVENTS

data "aws_caller_identity" "current" {
}

data "aws_iam_policy_document" "topic_policy" {
  statement {
    actions   = ["sns:Publish"]
    resources = ["arn:aws:sns:*:*:${local.sns_topic.name}"]

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.pypi.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_s3_bucket_notification" "reindex" {
  bucket = aws_s3_bucket.pypi.id

  topic {
    filter_suffix = ".tar.gz"
    topic_arn     = aws_sns_topic.reindex.arn

    events = [
      "s3:ObjectCreated:*",
      "s3:ObjectRemoved:*",
    ]
  }
}

resource "aws_sns_topic" "reindex" {
  name   = local.sns_topic.name
  policy = data.aws_iam_policy_document.topic_policy.json
  tags   = local.sns_topic.tags
}

resource "aws_sns_topic_subscription" "reindex" {
  endpoint  = aws_lambda_alias.reindex.arn
  protocol  = "lambda"
  topic_arn = aws_sns_topic.reindex.arn
}

# IAM

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
    sid       = "ReindexS3"
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
}

resource "aws_iam_role_policy" "policy" {
  name   = local.iam_role.policy_name
  role   = aws_iam_role.role.id
  policy = data.aws_iam_policy_document.policy.json
}

# LAMBDA :: API PROXY

resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/lambda/${aws_lambda_function.api.function_name}"
  retention_in_days = local.log_group_api.retention_in_days
  tags              = local.log_group_api.tags
}

resource "aws_lambda_alias" "api" {
  name             = local.lambda_api.alias_name
  function_name    = aws_lambda_function.api.arn
  function_version = local.lambda_api.alias_function_version
}

resource "aws_lambda_function" "api" {
  description      = local.lambda_api.description
  filename         = local.lambda.filename
  function_name    = local.lambda_api.function_name
  handler          = "index.proxy_request"
  memory_size      = local.lambda_api.memory_size
  publish          = local.lambda_api.publish
  role             = aws_iam_role.role.arn
  runtime          = local.lambda.runtime
  source_code_hash = local.lambda.source_code_hash
  tags             = local.lambda_api.tags

  environment {
    variables = {
      FALLBACK_INDEX_URL   = local.lambda_api.fallback_index_url
      S3_BUCKET            = aws_s3_bucket.pypi.bucket
      S3_PRESIGNED_URL_TTL = local.s3.presigned_url_ttl
    }
  }
}

resource "aws_lambda_permission" "invoke_api" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_alias.api.function_name
  principal     = "apigateway.amazonaws.com"
  qualifier     = aws_lambda_alias.api.name
  source_arn    = "${local.http_api.execution_arn}/*/*/*"
  statement_id  = "InvokeAPI"
}

# LAMBDA :: REINDEXER

resource "aws_cloudwatch_log_group" "reindex" {
  name              = "/aws/lambda/${aws_lambda_function.reindex.function_name}"
  retention_in_days = local.log_group_reindex.retention_in_days
  tags              = local.log_group_reindex.tags
}

resource "aws_lambda_alias" "reindex" {
  name             = local.lambda_reindex.alias_name
  function_name    = aws_lambda_function.reindex.arn
  function_version = local.lambda_reindex.alias_function_version
}

resource "aws_lambda_function" "reindex" {
  description      = local.lambda_reindex.description
  filename         = local.lambda.filename
  function_name    = local.lambda_reindex.function_name
  handler          = "index.reindex_bucket"
  memory_size      = local.lambda_reindex.memory_size
  publish          = local.lambda_reindex.publish
  role             = aws_iam_role.role.arn
  runtime          = local.lambda.runtime
  source_code_hash = local.lambda.source_code_hash
  tags             = local.lambda_reindex.tags

  environment {
    variables = {
      S3_BUCKET = aws_s3_bucket.pypi.bucket
    }
  }
}

resource "aws_lambda_permission" "reindex" {
  statement_id  = "Reindex"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_alias.reindex.function_name
  principal     = "sns.amazonaws.com"
  qualifier     = aws_lambda_alias.reindex.name
  source_arn    = aws_sns_topic.reindex.arn
}

# API GATEWAY :: HTTP INTEGRATIONS

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = local.http_api.id
  connection_type        = "INTERNET"
  description            = "PyPI proxy handler"
  integration_method     = "POST"
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_alias.api.invoke_arn
  payload_format_version = "2.0"
}

# API GATEWAY :: HTTP ROUTES

resource "aws_apigatewayv2_route" "root_get" {
  api_id             = local.http_api.id
  route_key          = "GET /"
  authorization_type = "NONE"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "root_head" {
  api_id             = local.http_api.id
  route_key          = "HEAD /"
  authorization_type = "NONE"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "root_post" {
  api_id             = local.http_api.id
  route_key          = "POST /"
  authorization_type = "NONE"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "proxy_get" {
  api_id             = local.http_api.id
  route_key          = "GET /{proxy+}"
  authorization_type = "NONE"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "proxy_head" {
  api_id             = local.http_api.id
  route_key          = "HEAD /{proxy+}"
  authorization_type = "NONE"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "proxy_post" {
  api_id             = local.http_api.id
  route_key          = "POST /{proxy+}"
  authorization_type = "NONE"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}
