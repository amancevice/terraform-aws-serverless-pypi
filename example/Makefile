BUCKET   := serverless-pypi-us-west-2
ENDPOINT := $(shell terraform output -raw endpoint)

curl:
	curl -s $(ENDPOINT)/requests-iamauth/ | prettier --parser html | bat -l html

logs:
	aws logs describe-log-groups --region us-west-2 \
	| jq -r '.logGroups[].logGroupName' \
	| grep serverless-pypi \
	| fzf --no-info --reverse \
	| xargs aws logs tail --follow

upload:
	curl -so- https://files.pythonhosted.org/packages/d0/d5/a2263aede309463cec2a1a5046b9e5b314b7ed4a8273c7c214af619700bb/requests-iamauth-0.3.0.tar.gz#sha256=189cc26ccf641afb8e7f1ec4a16f902f70bf57d818075c08412d0d86d4b04729 \
	| aws s3 cp - s3://$(BUCKET)/requests-iamauth/requests-iamauth-0.3.0.tar.gz

.PHONY: curl logs upload
