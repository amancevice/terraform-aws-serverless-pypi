###########
#   AWS   #
###########

provider "aws" {
  region = "us-west-2"

  default_tags { tags = { Name = "serverless-pypi-example" } }
}

###########
#   DNS   #
###########

variable "domain_name" { type = string }

data "aws_route53_zone" "zone" {
  name = var.domain_name
}

resource "aws_acm_certificate" "pypi" {
  domain_name       = "pypi.${data.aws_route53_zone.zone.name}"
  validation_method = "DNS"

  lifecycle { create_before_destroy = true }
}

resource "aws_acm_certificate_validation" "pypi" {
  certificate_arn         = aws_acm_certificate.pypi.arn
  validation_record_fqdns = [for record in aws_route53_record.ssl : record.fqdn]
}

resource "aws_api_gateway_domain_name" "pypi" {
  domain_name              = "pypi.${var.domain_name}"
  regional_certificate_arn = aws_acm_certificate.pypi.arn

  endpoint_configuration { types = ["REGIONAL"] }
}

resource "aws_api_gateway_base_path_mapping" "pypi" {
  api_id      = aws_api_gateway_rest_api.pypi.id
  base_path   = aws_api_gateway_stage.simple.stage_name
  domain_name = aws_api_gateway_domain_name.pypi.domain_name
  stage_name  = aws_api_gateway_stage.simple.stage_name
}

resource "aws_route53_record" "ssl" {
  for_each = {
    for dvo in aws_acm_certificate.pypi.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.zone.zone_id
}

resource "aws_route53_record" "pypi" {
  name    = aws_api_gateway_domain_name.pypi.domain_name
  type    = "A"
  zone_id = data.aws_route53_zone.zone.id

  alias {
    evaluate_target_health = true
    name                   = aws_api_gateway_domain_name.pypi.regional_domain_name
    zone_id                = aws_api_gateway_domain_name.pypi.regional_zone_id
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

output "endpoint" { value = "https://${aws_api_gateway_base_path_mapping.pypi.domain_name}/${aws_api_gateway_base_path_mapping.pypi.base_path}/" }
