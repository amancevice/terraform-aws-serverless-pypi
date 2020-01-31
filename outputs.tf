output api {
  description = "PyPI REST API."
  value       = aws_api_gateway_rest_api.api
}

output bucket {
  description = "PyPI S3 bucket."
  value       = aws_s3_bucket.pypi
}

output lambda {
  description = "PyPI REST API Lambda proxy."
  value       = aws_lambda_function.api
}

output role {
  description = "PyPI REST API Lambda IAM role."
  value       = aws_iam_role.role
}
