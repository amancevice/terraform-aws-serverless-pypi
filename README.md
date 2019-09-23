# Serverless PyPI

S3-backed serverless PyPI.

Requests to your PyPI server will be proxied through a Lambda function that pulls content from an S3 bucket and reponds with the same HTML content that you might find in a conventional PyPI server.

Requests to the base path (eg, `/simple/`) will respond with the contents of an `index.html` file at the root of your S3 bucket.

Requests to the package index (eg, `/simple/fizz/`) will dynamically generate an HTML file based on the contents of keys under that namespace (eg, `s3://your-bucket/fizz/`). URLs for package downloads are presigned S3 URLs with a default lifespan of 15 minutes.

Package uploads/removals on S3 will trigger a Lambda function that reindexes the bucket and generates a new `index.html`. This is done to save time when querying the base path when your bucket contains a multitude of packages.

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
  s3_presigned_url_ttl         = 900
}
```
