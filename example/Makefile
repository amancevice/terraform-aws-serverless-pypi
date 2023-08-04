BUCKET   := us-west-2-serverless-pypi
ENDPOINT := $(shell terraform output -raw endpoint)

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

.PHONY: curl logs ls upload

requests_iamauth-%-py3-none-any.whl:
	pip download --no-deps requests-iamauth==$*
