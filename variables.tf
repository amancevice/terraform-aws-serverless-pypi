variable api_authorization {
  default     = "NONE"
  description = "API Gateway method authorization [NONE | CUSTOM | AWS_IAM | COGNITO_USER_POOLS]."
}

variable api_base_path {
  default     = "simple"
  description = "Root resource for PyPI index."
}

variable api_description {
  default     = "PyPI service"
  description = "API Gateway REST API description."
}

variable api_endpoint_configuration_type {
  default     = "REGIONAL"
  description = "API Gateway endpoint configuration type [EDGE | REGIONAL | PRIVATE]."
}

variable api_name {
  description = "API Gateway REST API name."
}

variable lambda_description_api {
  default     = "PyPI service REST API"
  description = "Lambda function for REST API description."
}

variable lambda_description_reindex {
  default     = "Reindex PyPI root"
  description = "Lambda function decription for reindexer."
}

variable lambda_function_name_api {
  description = "Lambda function name for REST API."
}

variable lambda_function_name_reindex {
  description = "Lambda function name for reindexer."
}

variable log_group_retention_in_days {
  default     = 30
  description = "CloudWatch log group retention period."
}

variable policy_name {
  default     = "pypi-lambda-permissions"
  description = "IAM role inline policy name."
}

variable role_description {
  default     = "PyPI Lambda permissions"
  description = "IAM role description for Lambda functions."
}

variable role_name {
  description = "IAM role name for Lambda functions."
}

variable s3_bucket_name {
  description = "S3 bucket name for PyPI index."
}

variable s3_presigned_url_ttl {
  default     = 900
  description = "Presigned URL for PyPI package expiration in seconds."
}

variable tags {
  description = "Tags for resources in module."
  type        = map
  default     = {}
}
