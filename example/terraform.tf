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

resource "aws_api_gateway_rest_api" "pypi" {
  description = "Serverless PyPI example"
  name        = "serverless-pypi"

  endpoint_configuration { types = ["REGIONAL"] }
}

resource "aws_api_gateway_deployment" "pypi" {
  rest_api_id = aws_api_gateway_rest_api.pypi.id

  triggers = { redeployment = module.serverless_pypi.api_deployment_trigger }

  lifecycle { create_before_destroy = true }
}

resource "aws_api_gateway_stage" "simple" {
  deployment_id = aws_api_gateway_deployment.pypi.id
  rest_api_id   = aws_api_gateway_rest_api.pypi.id
  stage_name    = "simple"
}

#######################
#   SERVERLESS PYPI   #
#######################

module "serverless_pypi" {
  source = "./.."

  api_id                              = aws_api_gateway_rest_api.pypi.id
  api_execution_arn                   = aws_api_gateway_rest_api.pypi.execution_arn
  api_root_resource_id                = aws_api_gateway_rest_api.pypi.root_resource_id
  event_rule_name                     = "serverless-pypi-reindex"
  iam_role_name                       = "us-west-2-serverless-pypi"
  lambda_api_fallback_index_url       = "https://pypi.org/simple/"
  lambda_api_function_name            = "serverless-pypi-api"
  lambda_reindex_function_name        = "serverless-pypi-reindex"
  lambda_reindex_timeout              = 14
  log_group_api_retention_in_days     = 14
  log_group_reindex_retention_in_days = 14
  s3_bucket_name                      = "us-west-2-serverless-pypi"
}

###############
#   OUTPUTS   #
###############

output "endpoint" { value = "${aws_api_gateway_stage.simple.invoke_url}/" }
