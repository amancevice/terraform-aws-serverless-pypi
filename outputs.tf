output "api_deployment_trigger" {
  description = "API Gateway deployment trigger"

  value = sha1(jsonencode(concat(
    [aws_api_gateway_resource.proxy.id],
    [for x in aws_api_gateway_integration.integrations : x.id],
    [for x in aws_api_gateway_method.methods : x.id],
  )))
}

output "api_integrations" {
  description = "API Gateway integrations"
  value       = aws_api_gateway_integration.integrations
}

output "api_methods" {
  description = "API Gateway methods"
  value       = aws_api_gateway_method.methods
}

output "api_resources" {
  description = "API Gateway resources"
  value       = [aws_api_gateway_resource.proxy]
}

output "s3_bucket" {
  description = "PyPI S3 bucket"
  value       = aws_s3_bucket.pypi
}

output "iam_role" {
  description = "PyPI API Lambda IAM role"
  value       = aws_iam_role.role
}

output "lambda_api" {
  description = "PyPI API proxy Lambda function"
  value       = aws_lambda_function.api
}

output "lambda_api_log_group" {
  description = "PyPI API proxy Lambda function CloudWatch log group"
  value       = aws_cloudwatch_log_group.api
}

output "lambda_reindex" {
  description = "Reindexer Lambda function"
  value       = aws_lambda_function.reindex
}

output "lambda_reindex_log_group" {
  description = "Reindexer Lambda function CloudWatch log group"
  value       = aws_cloudwatch_log_group.reindex
}

output "sns_topic" {
  description = "Reindexer SNS topic"
  value       = aws_sns_topic.reindex
}
