variable "api_authorization_type" {
  description = "API Gateway REST API routes authorization type"
  default     = "NONE"
}

variable "api_authorizer_id" {
  description = "API Gateway REST API routes authorizer ID"
  default     = null
}

variable "api_id" {
  description = "API Gateway REST API ID"
}

variable "api_execution_arn" {
  description = "API Gateway REST API execution ARN"
}

variable "api_root_resource_id" {
  description = "API Gateway REST API root resource ID"
}

variable "iam_role_description" {
  description = "Lambda function IAM role description"
  default     = "PyPI Lambda permissions"
}

variable "iam_role_name" {
  description = "Lambda function role name"
}

variable "iam_role_policy_name" {
  description = "IAM role inline policy name"
  default     = "pypi-lambda-permissions"
}

variable "iam_role_tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}

variable "lambda_api_alias_name" {
  description = "PyPI API Lambda alias name"
  default     = "prod"
}

variable "lambda_api_alias_function_version" {
  description = "PyPI API Lambda alias target function version"
  default     = "$LATEST"
}

variable "lambda_api_description" {
  description = "REST API Lambda function description"
  default     = "PyPI service REST API"
}

variable "lambda_api_fallback_index_url" {
  description = "Optional fallback PyPI index URL"
  default     = null
}

variable "lambda_api_function_name" {
  description = "PyPI API Lambda function name"
}

variable "lambda_api_memory_size" {
  description = "PyPI API Lambda function memory size"
  default     = 128
}

variable "lambda_api_publish" {
  description = "PyPI API Lambda function publish trigger"
  type        = bool
  default     = false
}

variable "lambda_api_tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}

variable "lambda_api_timeout" {
  description = "Lambda function timeout"
  default     = 3
}

variable "lambda_reindex_alias_name" {
  description = "Reindexer Lambda alias name"
  default     = "prod"
}

variable "lambda_reindex_alias_function_version" {
  description = "Reindexer Lambda alias target function version"
  default     = "$LATEST"
}

variable "lambda_reindex_description" {
  description = "Reindexer Lambda function decription"
  default     = "PyPI service reindexer"
}

variable "lambda_reindex_function_name" {
  description = "Reindexer Lambda function name"
}

variable "lambda_reindex_memory_size" {
  description = "Reindexer Lambda function memory size"
  default     = 128
}

variable "lambda_reindex_publish" {
  description = "Reindexer Lambda function publish true/false"
  type        = bool
  default     = false
}

variable "lambda_reindex_tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}

variable "lambda_reindex_timeout" {
  description = "Lambda function timeout"
  default     = 3
}

variable "lambda_runtime" {
  description = "Lambda runtime"
  default     = "python3.9"
}

variable "log_group_api_retention_in_days" {
  description = "CloudWatch log group retention period"
  default     = 0
}

variable "log_group_api_tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}

variable "log_group_reindex_retention_in_days" {
  description = "CloudWatch log group retention period"
  default     = 0
}

variable "log_group_reindex_tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}

variable "s3_bucket_name" {
  description = "PyPI index S3 bucket name"
}

variable "s3_bucket_tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}

variable "s3_presigned_url_ttl" {
  description = "PyPI package presigned URL expiration in seconds"
  default     = 900
}

variable "sns_topic_name" {
  description = "SNS Topic name"
}

variable "sns_topic_tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
