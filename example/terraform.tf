###########
#   AWS   #
###########

provider "aws" {
  region = local.region

  default_tags { tags = { Name = local.name } }
}

##############
#   LOCALS   #
##############

locals {
  region = "us-east-1"
  name   = "serverless-pypi"
}

###########
#   DNS   #
###########

variable "domain_name" { type = string }

data "aws_route53_zone" "zone" {
  name = var.domain_name
}

data "aws_acm_certificate" "ssl" {
  domain   = var.domain_name
  statuses = ["ISSUED"]
}

resource "aws_api_gateway_domain_name" "pypi" {
  domain_name              = "pypi.${var.domain_name}"
  regional_certificate_arn = data.aws_acm_certificate.ssl.arn

  endpoint_configuration { types = ["REGIONAL"] }
}

resource "aws_api_gateway_base_path_mapping" "pypi" {
  api_id      = aws_api_gateway_rest_api.pypi.id
  base_path   = aws_api_gateway_stage.simple.stage_name
  domain_name = aws_api_gateway_domain_name.pypi.domain_name
  stage_name  = aws_api_gateway_stage.simple.stage_name
}

resource "aws_route53_record" "pypi" {
  for_each = toset(["A", "AAAA"])

  name           = aws_api_gateway_domain_name.pypi.domain_name
  set_identifier = local.region
  type           = each.key
  zone_id        = data.aws_route53_zone.zone.id

  alias {
    evaluate_target_health = false
    name                   = aws_api_gateway_domain_name.pypi.regional_domain_name
    zone_id                = aws_api_gateway_domain_name.pypi.regional_zone_id
  }

  latency_routing_policy {
    region = local.region
  }
}

##################
#   API GATEWAY  #
##################

resource "aws_api_gateway_rest_api" "pypi" {
  description                  = "Serverless PyPI example"
  disable_execute_api_endpoint = true
  name                         = "serverless-pypi"

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
  event_rule_name                     = "${local.name}-reindex"
  iam_role_name                       = "${local.region}-${local.name}"
  lambda_api_fallback_index_url       = "https://pypi.org/simple/"
  lambda_api_function_name            = "${local.name}-api"
  lambda_reindex_function_name        = "${local.name}-reindex"
  lambda_reindex_timeout              = 14
  log_group_api_retention_in_days     = 14
  log_group_reindex_retention_in_days = 14
  s3_bucket_name                      = "${local.region}-${local.name}"
}

###############
#   OUTPUTS   #
###############

output "endpoint" { value = "https://${aws_api_gateway_base_path_mapping.pypi.domain_name}/${aws_api_gateway_base_path_mapping.pypi.base_path}/" }
