.PHONY: default clean test up validate

default: test validate

.terraform:
	terraform init

clean:
	rm -rf .terraform

test:
	flake8
	pytest

up:
	lambda-gateway index.proxy_request -B simple

validate: | .terraform
	terraform validate
