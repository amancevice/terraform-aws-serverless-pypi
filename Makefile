package.zip: index.py | validate
	zip $@ $^

.terraform:
	terraform init

.PHONY: clean test up validate

clean:
	rm -rf .terraform

test:
	flake8 index.py index_test.py
	pytest index_test.py

up:
	lambda-gateway index.proxy_request -B simple

validate: test | .terraform
	terraform validate
