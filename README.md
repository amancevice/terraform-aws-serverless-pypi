# Serverless PyPI

[![terraform](https://img.shields.io/github/v/tag/amancevice/terraform-aws-serverless-pypi?color=62f&label=version&logo=terraform&style=flat-square)](https://registry.terraform.io/modules/amancevice/serverless-pypi/aws)
[![py.test](https://img.shields.io/github/workflow/status/amancevice/terraform-aws-serverless-pypi/py.test?logo=github&style=flat-square)](https://github.com/amancevice/terraform-aws-serverless-pypi/actions)
[![coverage](https://img.shields.io/codeclimate/coverage/amancevice/terraform-aws-serverless-pypi?logo=code-climate&style=flat-square)](https://codeclimate.com/github/amancevice/terraform-aws-serverless-pypi/test_coverage)
[![maintainability](https://img.shields.io/codeclimate/maintainability/amancevice/terraform-aws-serverless-pypi?logo=code-climate&style=flat-square)](https://codeclimate.com/github/amancevice/terraform-aws-serverless-pypi/maintainability)

S3-backed serverless PyPI.

Requests to your PyPI server will be proxied through a Lambda function that pulls content from an S3 bucket and responds with the same HTML content that you might find in a conventional PyPI server.

Requests to the base path (eg, `/simple/`) will respond with the contents of an `index.html` file at the root of your S3 bucket.

Requests to the package index (eg, `/simple/fizz/`) will dynamically generate an HTML file based on the contents of keys under that namespace (eg, `s3://your-bucket/fizz/`). URLs for package downloads are presigned S3 URLs with a default lifespan of 15 minutes.

Package uploads/removals on S3 will trigger a Lambda function that reindexes the bucket and generates a new `index.html`. This is done to save time when querying the base path when your bucket contains a multitude of packages.

[![Serverless PyPI](https://github.com/amancevice/terraform-aws-serverless-pypi/blob/main/serverless-pypi.png?raw=true)](https://github.com/amancevice/terraform-aws-serverless-pypi)

## Usage

As of v2 users are expected to bring-your-own REST API instead of providing one inside the module. This gives users greater flexibility in choosing how their API is set up.

Users can deploy their API inside a VPC, for example, or attach this module to a resource inside a pre-existing API in a "monolithic" approach to API Gateway management.

A very simple setup is as follows:

```terraform
resource "aws_api_gateway_rest_api" "pypi" {
  name = "serverless-pypi"
}

module "serverless_pypi" {
  source  = "amancevice/serverless-pypi/aws"
  version = "~> 2.0"

  # Custom names / config
  iam_role_name                = "serverless-pypi-role"
  lambda_api_function_name     = "serverless-pypi-api-proxy"
  lambda_reindex_function_name = "serverless-pypi-reindexer"
  s3_bucket_name               = "serverless-pypi.example.com"
  s3_presigned_url_ttl         = 900

  # API Gateway config
  rest_api_execution_arn    = aws_api_gateway_rest_api.pypi.execution_arn
  rest_api_id               = aws_api_gateway_rest_api.pypi.id
  rest_api_root_resource_id = aws_api_gateway_rest_api.pypi.root_resource_id

  # etc...
}
```

## S3 Bucket Organization

This tool is highly opinionated about how your S3 bucket is organized. Your root key space should only contain the auto-generated `index.html` and "directories" of your PyPI packages.

Packages should exist one level deep in the bucket where the prefix is the name of the project.

Example:

```
s3://your-bucket/
├── index.html
├── my-cool-package/
│   ├── my-cool-package-0.1.2.tar.gz
│   ├── my-cool-package-1.2.3.tar.gz
│   └── my-cool-package-2.3.4.tar.gz
└── my-other-package/
    ├── my-other-package-0.1.2.tar.gz
    ├── my-other-package-1.2.3.tar.gz
    └── my-other-package-2.3.4.tar.gz
```

## Fallback PyPI Index

You can configure your PyPI index to fall back to a different PyPI in the event that a package is not found in your bucket.

Without configuring a fallback index URL the following `pip install` command might fail (assuming you don't have `boto3` and all its dependencies in your S3 bucket):

```bash
pip install boto3 --index-url https://my.private.pypi/simple/
```

If instead, you configure a fallback index URL in the terraform module, then requesting a pip that isn't found in the bucket will be re-routed to the fallback.

```terraform
module "serverless_pypi" {
  source  = "amancevice/serverless-pypi/aws"
  version = "~> 2.0"

  lambda_api_fallback_index_url = "https://pypi.org/simple/"

  # etc...
}
```

## Auth

Please note that this tool provides **NO** authentication layer for your PyPI index out of the box. This is difficult to implement because `pip` is currently not very forgiving with any kind of auth pattern outside Basic Auth.

### Cognito Basic Auth

I have provided a very simple authentication implementation using AWS Cognito and API Gateway authorizers.

Add a Cognito-backed Basic authentication layer to your serverless PyPI with the `serverless-pypi-cognito` module:

```terraform
module "serverless_pypi_cognito" {
  source  = "amancevice/serverless-pypi-cognito/aws"
  version = "~> 1.0"

  cognito_user_pool_name = "serverless-pypi-cognito-pool"
  iam_role_name          = "serverless-pypi-authorizer-role"
  lambda_function_name   = "serverless-pypi-authorizer"
  rest_api_id            = aws_api_gateway_rest_api.pypi.id

}
```

You will also need to update your serverless PyPI module with the authorizer ID and authorization strategy:

```terraform
module "serverless_pypi" {
  source  = "amancevice/serverless-pypi/aws"
  version = "~> 2.0"

  rest_api_authorization = "CUSTOM"
  rest_api_authorizer_id = module.serverless_pypi_cognito.rest_api_authorizer.id

  # etc...
}
```
