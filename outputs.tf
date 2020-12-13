output "bucket" {
  description = "PyPI S3 bucket"
  value       = aws_s3_bucket.pypi
}

output "iam_role" {
  description = "PyPI REST API Lambda IAM role"
  value       = aws_iam_role.role
}

output "lambda_api" {
  description = "PyPI REST API proxy Lambda function"
  value       = aws_lambda_function.api
}

output "lambda_reindex" {
  description = "Reindexer Lambda function"
  value       = aws_lambda_function.reindex
}
