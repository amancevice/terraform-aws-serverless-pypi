.PHONY: clean test up validate

package.zip: index.py | validate
	zip $@ $^

coverage.xml: index*.py
	flake8 $^
	pytest

.terraform:
	terraform init

clean:
	rm -rf .terraform

test: coverage.xml

up:
	lambda-gateway index.proxy_request -B simple

validate: coverage.xml | .terraform
	terraform fmt -check
	terraform validate
