BUCKET   := us-west-2-serverless-pypi
ENDPOINT := $(shell terraform output -raw endpoint)

all: validate

clean:
	rm -rf .terraform*

curl:
	curl -s $(ENDPOINT)requests-iamauth/ | prettier --parser html | bat -l html

logs:
	aws logs describe-log-groups --region us-west-2 \
	| jq -r '.logGroups[].logGroupName' \
	| grep serverless-pypi \
	| fzf --no-info --reverse \
	| xargs aws logs tail --follow

ls:
	aws s3 ls s3://$(BUCKET)/ --recursive

upload: requests_iamauth-0.7.0-py3-none-any.whl
	aws s3 cp $< s3://$(BUCKET)/requests-iamauth/$<

validate: | .terraform
	terraform fmt -check
	AWS_REGION=us-east-1 terraform validate

.PHONY: all curl logs ls upload validate

requests_iamauth-%-py3-none-any.whl:
	pip download --no-deps requests-iamauth==$*

.terraform: ../*.tf
	terraform init
	touch $@
