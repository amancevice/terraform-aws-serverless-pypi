all: validate

clean:
	rm -rf .terraform*

up: .env
	pipenv run python -m lambda_gateway index.proxy_request

validate: Pipfile.lock | .terraform
	pipenv run pytest
	terraform fmt -check
	AWS_REGION=us-east-1 terraform validate

.PHONY: all clean up validate

.env:
	touch $@

.terraform:
	terraform init

Pipfile.lock: Pipfile
	pipenv install --dev
