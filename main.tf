terraform {
  required_version = ">= 0.12.0"
}

locals {
  api_authorization               = var.api_authorization
  api_base_path                   = var.api_base_path
  api_description                 = var.api_description
  api_endpoint_configuration_type = var.api_endpoint_configuration_type
  api_name                        = var.api_name
  lambda_description_api          = var.lambda_description_api
  lambda_description_reindex      = var.lambda_description_reindex
  lambda_function_name_api        = var.lambda_function_name_api
  lambda_function_name_reindex    = var.lambda_function_name_reindex
  lambda_handler_api              = "index.handler"
  lambda_handler_reindex          = "index.reindex"
  lambda_runtime                  = "python3.8"
  log_group_retention_in_days     = var.log_group_retention_in_days
  policy_name                     = var.policy_name
  role_description                = var.role_description
  role_name                       = var.role_name
  s3_bucket_name                  = var.s3_bucket_name
  s3_presigned_url_ttl            = var.s3_presigned_url_ttl
  tags                            = var.tags
}

data archive_file package {
  source_file = "${path.module}/index.py"
  output_path = "${path.module}/package.zip"
  type        = "zip"
}

data aws_iam_policy_document assume_role {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data aws_iam_policy_document api {
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
    sid = "WriteLambdaLogs"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["*"]
  }
}

resource aws_api_gateway_integration proxy_get {
  content_handling        = "CONVERT_TO_TEXT"
  http_method             = aws_api_gateway_method.proxy_get.http_method
  integration_http_method = "POST"
  resource_id             = aws_api_gateway_resource.proxy.id
  rest_api_id             = aws_api_gateway_rest_api.api.id
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api.invoke_arn
}

resource aws_api_gateway_integration root_get {
  content_handling        = "CONVERT_TO_TEXT"
  http_method             = aws_api_gateway_method.proxy_get.http_method
  integration_http_method = "POST"
  resource_id             = aws_api_gateway_rest_api.api.root_resource_id
  rest_api_id             = aws_api_gateway_rest_api.api.id
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api.invoke_arn
}

resource aws_api_gateway_method proxy_get {
  authorization = local.api_authorization
  http_method   = "GET"
  resource_id   = aws_api_gateway_resource.proxy.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
}

resource aws_api_gateway_method root_get {
  authorization = local.api_authorization
  http_method   = "GET"
  resource_id   = aws_api_gateway_rest_api.api.root_resource_id
  rest_api_id   = aws_api_gateway_rest_api.api.id
}

resource aws_api_gateway_resource proxy {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "{proxy+}"
}

resource aws_api_gateway_rest_api api {
  description = local.api_description
  name        = local.api_name

  endpoint_configuration {
    types = [local.api_endpoint_configuration_type]
  }
}

resource aws_cloudwatch_log_group api {
  name              = "/aws/lambda/${aws_lambda_function.api.function_name}"
  retention_in_days = local.log_group_retention_in_days
  tags              = local.tags
}

resource aws_cloudwatch_log_group reindex {
  name              = "/aws/lambda/${aws_lambda_function.reindex.function_name}"
  retention_in_days = local.log_group_retention_in_days
  tags              = local.tags
}

resource aws_iam_role role {
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  description        = local.role_description
  name               = local.role_name
  tags               = local.tags
}

resource aws_iam_role_policy policy {
  name   = local.policy_name
  role   = aws_iam_role.role.id
  policy = data.aws_iam_policy_document.api.json
}

resource aws_lambda_function api {
  description      = local.lambda_description_api
  filename         = data.archive_file.package.output_path
  function_name    = local.lambda_function_name_api
  handler          = local.lambda_handler_api
  role             = aws_iam_role.role.arn
  runtime          = local.lambda_runtime
  source_code_hash = data.archive_file.package.output_base64sha256
  tags             = local.tags

  environment {
    variables = {
      S3_BUCKET            = aws_s3_bucket.pypi.bucket
      S3_PRESIGNED_URL_TTL = local.s3_presigned_url_ttl
      BASE_PATH            = local.api_base_path
    }
  }
}

resource aws_lambda_function reindex {
  description      = local.lambda_description_reindex
  filename         = data.archive_file.package.output_path
  function_name    = local.lambda_function_name_reindex
  handler          = local.lambda_handler_reindex
  role             = aws_iam_role.role.arn
  runtime          = local.lambda_runtime
  source_code_hash = data.archive_file.package.output_base64sha256
  tags             = local.tags

  environment {
    variables = {
      S3_BUCKET = aws_s3_bucket.pypi.bucket
    }
  }
}

resource aws_lambda_permission invoke_api {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*/*"
}

resource aws_lambda_permission invoke_reindex {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.reindex.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.pypi.arn
}

resource aws_s3_bucket pypi {
  acl    = "private"
  bucket = local.s3_bucket_name
  tags   = local.tags
}

resource aws_s3_bucket_notification reindex {
  bucket = aws_s3_bucket.pypi.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.reindex.arn
    events              = ["s3:ObjectCreated:*", "s3:ObjectRemoved:*"]
    filter_suffix       = ".tar.gz"
  }
}

resource aws_s3_bucket_public_access_block pypi {
  block_public_acls       = true
  block_public_policy     = true
  bucket                  = aws_s3_bucket.pypi.id
  ignore_public_acls      = true
  restrict_public_buckets = true
}
