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
      version = "~> 4.0"
    }
  }
}

###########
#   AWS   #
###########

provider "aws" {
  region = "us-west-2"

  default_tags { tags = { Name = "serverless-pypi-example" } }
}

##################
#   API GATEWAY  #
##################

resource "aws_apigatewayv2_api" "pypi" {
  description   = "Serverless PyPI example"
  name          = "serverless-pypi"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.pypi.id
  auto_deploy = true
  name        = "simple"

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_logs.arn

    format = jsonencode({
      httpMethod     = "$context.httpMethod"
      ip             = "$context.identity.sourceIp"
      protocol       = "$context.protocol"
      requestId      = "$context.requestId"
      requestTime    = "$context.requestTime"
      responseLength = "$context.responseLength"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
    })
  }
}

resource "aws_cloudwatch_log_group" "api_logs" {
  name              = "/aws/apigatewayv2/${aws_apigatewayv2_api.pypi.name}"
  retention_in_days = 14
}

#######################
#   SERVERLESS PYPI   #
#######################

module "serverless_pypi" {
  source = "./.."

  api_id                              = aws_apigatewayv2_api.pypi.id
  api_execution_arn                   = aws_apigatewayv2_api.pypi.execution_arn
  iam_role_name                       = "serverless-pypi"
  lambda_api_fallback_index_url       = "https://pypi.org/simple/"
  lambda_api_function_name            = "serverless-pypi-api"
  lambda_api_publish                  = false
  lambda_reindex_function_name        = "serverless-pypi-reindex"
  lambda_reindex_publish              = false
  lambda_reindex_timeout              = 14
  log_group_api_retention_in_days     = 14
  log_group_reindex_retention_in_days = 14
  s3_bucket_name                      = "serverless-pypi-us-west-2"
  sns_topic_name                      = "serverless-pypi"
}

###############
#   OUTPUTS   #
###############

output "endpoint" { value = "${aws_apigatewayv2_api.pypi.api_endpoint}/simple/" }
