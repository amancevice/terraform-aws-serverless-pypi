output bucket {
  description = "PyPI S3 bucket"
  value       = aws_s3_bucket.pypi
}

output lambda_api {
  description = "PyPI REST API proxy Lambda function"
  value       = aws_lambda_function.api
}

output lambda_reindex {
  description = "Reindexer Lambda function"
  value       = aws_lambda_function.reindex
}

output rest_api_redeployment_trigger {
  description = "API Gateway REST API redeployment trigger"
  value = sha1(join(",", list(
    jsonencode(aws_api_gateway_integration.root_get),
    jsonencode(aws_api_gateway_integration.root_head),
    jsonencode(aws_api_gateway_integration.root_post),
    jsonencode(aws_api_gateway_integration.proxy_get),
    jsonencode(aws_api_gateway_integration.proxy_head),
    jsonencode(aws_api_gateway_integration.proxy_post),
  )))
}

output rest_api_integration_root_get {
  description = "API Gateway REST API GET / integration"
  value       = aws_api_gateway_integration.root_get
}

output rest_api_integration_root_head {
  description = "API Gateway REST API HEAD / integration"
  value       = aws_api_gateway_integration.root_head
}

output rest_api_integration_root_post {
  description = "API Gateway REST API POST / integration"
  value       = aws_api_gateway_integration.root_post
}

output rest_api_integration_proxy_get {
  description = "API Gateway REST API GET /{proxy+} integration"
  value       = aws_api_gateway_integration.proxy_get
}

output rest_api_integration_proxy_head {
  description = "API Gateway REST API HEAD /{proxy+} integration"
  value       = aws_api_gateway_integration.proxy_head
}

output rest_api_integration_proxy_post {
  description = "API Gateway REST API POST /{proxy+} integration"
  value       = aws_api_gateway_integration.proxy_post
}

output role {
  description = "PyPI REST API Lambda IAM role"
  value       = aws_iam_role.role
}
