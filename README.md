# Serverless PyPI

[![py.test](https://github.com/amancevice/terraform-aws-serverless-pypi/workflows/py.test/badge.svg)](https://github.com/amancevice/terraform-aws-serverless-pypi/actions)
[![Maintainability](https://api.codeclimate.com/v1/badges/7198bd49152ff23fbe93/maintainability)](https://codeclimate.com/github/amancevice/terraform-aws-serverless-pypi/maintainability)
[![Test Coverage](https://api.codeclimate.com/v1/badges/7198bd49152ff23fbe93/test_coverage)](https://codeclimate.com/github/amancevice/terraform-aws-serverless-pypi/test_coverage)

S3-backed serverless PyPI.

Requests to your PyPI server will be proxied through a Lambda function that pulls content from an S3 bucket and reponds with the same HTML content that you might find in a conventional PyPI server.

Requests to the base path (eg, `/simple/`) will respond with the contents of an `index.html` file at the root of your S3 bucket.

Requests to the package index (eg, `/simple/fizz/`) will dynamically generate an HTML file based on the contents of keys under that namespace (eg, `s3://your-bucket/fizz/`). URLs for package downloads are presigned S3 URLs with a default lifespan of 15 minutes.

Package uploads/removals on S3 will trigger a Lambda function that reindexes the bucket and generates a new `index.html`. This is done to save time when querying the base path when your bucket contains a multitude of packages.

[![Serverless PyPI](https://github.com/amancevice/terraform-aws-serverless-pypi/blob/master/serverless-pypi.png?raw=true)](https://github.com/amancevice/terraform-aws-serverless-pypi)

## Usage

```hcl
module serverless_pypi {
  source  = "amancevice/serverless-pypi/aws"
  version = "~> 1.0"

  # ...
  api_name                       = "serverless-pypi.example.com"
  api_endpoint_configuation_type = "REGIONAL | EDGE | PRIVATE"
  lambda_api_function_name       = "serverless-pypi-api"
  lambda_reindex_function_name   = "serverless-pypi-reindex"
  role_name                      = "serverless-pypi-role"
  s3_bucket_name                 = "serverless-pypi.example.com"
  s3_presigned_url_ttl           = 900
  # ...
}
```

## S3 Bucket Organization

This tool is highly opinionated about how your S3 bucket is organized. Your root keyspace should only contain the auto-generated `index.html` and "directories" of your PyPI packages.

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

```hcl
module serverless_pypi {
  source  = "amancevice/serverless-pypi/aws"

  # ...
  fallback_index_url = "https://pypi.org/simple/"
  # ...
}
```

## Auth

Please note that this tool provides **NO** authentication layer for your PyPI server out of the box. This is difficult to implement because `pip` is currently not very forgiving with any kind of auth pattern outside Basic Auth.

### Cognito Basic Auth

I have provided a very simple authentication implementation using AWS Cognito and API Gateway authorizers.

Add a Cognito-backed Basic authentication layer to your serverless PyPI with the `serverless-pypi-cognito` module:

```hcl
module serverless_pypi_cognito {
  source               = "amancevice/serverless-pypi-cognito/aws"
  version              = "~> 0.2"
  api_id               = module.serverless_pypi.api.id
  lambda_function_name = "serverless-pypi-authorizer"
  role_name            = "serverless-pypi-authorizer-role"
  user_pool_name       = "serverless-pypi-cognito-pool"
}
```

You will also need to update your serverless PyPI module with the authorizer ID and authorization strategy:

```hcl
module serverless_pypi {
  source  = "amancevice/serverless-pypi/aws"

  # ...
  api_authorization = "CUSTOM"
  api_authorizer_id = module.serverless_pypi_cognito.authorizer.id
  # ...
}
```

### Private VPC Endpoint

Another solution to this is to deploy the API Gateway as a private endpoint inside a VPC. You will need to set up a VPC endpoint for this to work, however. Be warned that creating a VPC endpoint for API Gateway can have unintended consequences if you are not prepared. I've broken things by doing this.
