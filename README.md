# Serverless PyPI

S3-backed serverless PyPI.

[![Serverless PyPI](https://github.com/amancevice/terraform-aws-serverless-pypi/blob/master/serverless-pypi.png?raw=true)](https://github.com/amancevice/terraform-aws-serverless-pypi)

## Usage

```hcl
module serverless_pypi {
  source                       = "amancevice/serverless-pypi/aws"
  version =                    = "~> 0.1"
  api_name                     = "pypi.example.com"
  lambda_function_name_api     = "pypi-api"
  lambda_function_name_reindex = "pypi-reindex"
  role_name                    = "pypi-role"
  s3_bucket_name               = "pypi.example.com"
}
```
