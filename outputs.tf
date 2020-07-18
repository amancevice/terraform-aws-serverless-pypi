output bucket {
  description = "PyPI S3 bucket"
  value       = aws_s3_bucket.pypi
}

output lambda_api {
  description = "PyPI REST API proxy Lambda function"
  value       = aws_lambda_function.api
}

output lambda_api_arn {
  description = "PyPI REST API proxy Lambda function ARN"
  value       = local.lambda_api_arn
}

output lambda_reindex {
  description = "Reindexer Lambda function"
  value       = aws_lambda_function.reindex
}

output lambda_reindex_arn {
  description = "Reindexer Lambda function ARN"
  value       = local.lambda_reindex_arn
}

output role {
  description = "PyPI REST API Lambda IAM role"
  value       = aws_iam_role.role
}
