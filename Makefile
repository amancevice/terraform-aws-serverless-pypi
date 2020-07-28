package.zip: index.py | validate
	zip $@ $^

.terraform:
	terraform init

.PHONY: clean test up validate

clean:
	rm -rf .terraform

test:
	flake8
	pytest

up:
	lambda-gateway index.proxy_request -B simple

validate: test | .terraform
	terraform validate
