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
