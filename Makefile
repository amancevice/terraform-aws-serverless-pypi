all: test validate

clean:
	rm -rf .terraform*
	make -C python clean

test:
	make -C python test

validate: | .terraform
	terraform fmt -check
	AWS_REGION=us-east-1 terraform validate

.PHONY: test validate

.terraform:
	terraform init
