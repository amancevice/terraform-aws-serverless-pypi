REPO := cargometrics/serverless-pypi

all: validate

clean:
	rm -rf Dockerfile.iid

clobber: clean
	rm -rf .terraform*

shell: .env Dockerfile.iid
	docker run --interactive --rm --tty \
	--entrypoint bash \
	--env-file .env \
	--volume ~/.aws:/root/.aws \
	--volume $$PWD:/var/task \
	$(REPO)

up: .env Dockerfile.iid
	docker run --rm --tty \
	--entrypoint python \
	--env-file .env \
	--publish 8000:8000 \
	--volume ~/.aws:/root/.aws \
	--volume $$PWD:/var/task \
	$(REPO) -m lambda_gateway index.proxy_request

validate: Dockerfile.iid package.zip | .terraform
	docker run --rm --tty --entrypoint pytest --volume $$PWD:/var/task $(REPO)
	terraform fmt -check
	AWS_REGION=us-east-1 terraform validate

.PHONY: all clean clobber up validate

.env:
	touch $@

.terraform:
	terraform init

Dockerfile.iid: Dockerfile Pipfile
	docker build --iidfile $@ --tag $(REPO) .

Pipfile.lock: Dockerfile.iid
	docker run --rm --entrypoint cat $(REPO) $@ > $@

package.zip: index.py
	zip $@ $<
