# Serverless PyPI

[![terraform](https://img.shields.io/github/v/tag/amancevice/terraform-aws-serverless-pypi?color=62f&label=version&logo=terraform&style=flat-square)](https://registry.terraform.io/modules/amancevice/serverless-pypi/aws)
[![test](https://img.shields.io/github/actions/workflow/status/amancevice/terraform-aws-serverless-pypi/test.yml?logo=github&style=flat-square)](https://github.com/amancevice/terraform-aws-serverless-pypi/actions/workflows/test.yml)
[![coverage](https://img.shields.io/codeclimate/coverage/amancevice/terraform-aws-serverless-pypi?logo=code-climate&style=flat-square)](https://codeclimate.com/github/amancevice/terraform-aws-serverless-pypi/test_coverage)
[![maintainability](https://img.shields.io/codeclimate/maintainability/amancevice/terraform-aws-serverless-pypi?logo=code-climate&style=flat-square)](https://codeclimate.com/github/amancevice/terraform-aws-serverless-pypi/maintainability)

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/smallweirdnumber)

S3-backed serverless PyPI.

Requests to your PyPI server will be proxied through a Lambda function that pulls content from an S3 bucket and responds with the same HTML content that you might find in a conventional PyPI server.

Requests to the base path (eg, `/simple/`) will respond with the contents of an `index.html` file at the root of your S3 bucket.

Requests to the package index (eg, `/simple/fizz/`) will dynamically generate an HTML file based on the contents of keys under that namespace (eg, `s3://your-bucket/fizz/`). URLs for package downloads are presigned S3 URLs with a default lifespan of 15 minutes.

Package uploads/removals on S3 will trigger a Lambda function that reindexes the bucket and generates a new `index.html` at the root. This is done to save time when querying the base path when your bucket contains a multitude of packages.

![Serverless PyPI](./docs/serverless-pypi.png)

## Usage

As of v7 users are expected to bring-your-own REST API (v1). This gives users greater flexibility in choosing how their API is set up.

The most simplistic setup is as follows:

```terraform
#######################
#   SERVERLESS PYPI   #
#######################

module "serverless_pypi" {
  source  = "amancevice/serverless-pypi/aws"
  version = "~> 7"

  api_execution_arn             = aws_api_gateway_rest_api.pypi.execution_arn
  api_id                        = aws_api_gateway_rest_api.pypi.id
  api_root_resource_id          = aws_api_gateway_rest_api.pypi.root_resource_id
  event_rule_name               = "serverless-pypi-reindex"
  iam_role_name                 = "serverless-pypi"
  lambda_api_fallback_index_url = "https://pypi.org/simple/"
  lambda_api_function_name      = "serverless-pypi-api"
  lambda_reindex_function_name  = "serverless-pypi-reindex"
  s3_bucket_name                = "serverless-pypi-us-west-2"

  # etc …
}

################
#   REST API   #
################

resource "aws_api_gateway_rest_api" "pypi" {
  description = "Serverless PyPI example"
  name        = "serverless-pypi"

  endpoint_configuration { types = ["REGIONAL"] }
}

resource "aws_api_gateway_deployment" "pypi" {
  rest_api_id = aws_api_gateway_rest_api.pypi.id

  triggers = { redeployment = module.serverless_pypi.api_deployment_trigger }

  lifecycle { create_before_destroy = true }
}

resource "aws_api_gateway_stage" "simple" {
  deployment_id = aws_api_gateway_deployment.pypi.id
  rest_api_id   = aws_api_gateway_rest_api.pypi.id
  stage_name    = "simple"
}
```

## S3 Bucket Organization

This tool is highly opinionated about how your S3 bucket is organized. Your root key space should only contain the auto-generated `index.html` and "directories" of your PyPI packages.

Packages should exist one level deep in the bucket where the prefix is the name of the project.

Example:

```plain
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

Without configuring a fallback index URL the following `pip install` command will surely fail (assuming you don't have `boto3` and all its dependencies in your S3 bucket):

```bash
pip install boto3 --index-url https://my.private.pypi/simple/
```

Instead, if you configure a fallback index URL in the terraform module, then requests for a pip that isn't found in the bucket will be re-routed to the fallback.

```terraform
module "serverless_pypi" {
  source  = "amancevice/serverless-pypi/aws"
  version = "~> 7"

  lambda_api_fallback_index_url = "https://pypi.org/simple/"

  # etc …
}
```

## Auth

Please note that this tool provides **NO** authentication layer for your PyPI index out of the box. This is difficult to implement because `pip` is currently not very forgiving with any kind of auth pattern outside Basic Auth.

Using a REST API configured for a private VPC is the easiest solution to this problem, but you could also write a custom authorizer for your API as well.
