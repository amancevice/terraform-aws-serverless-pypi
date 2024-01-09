all: test

clean:
	pipenv --rm

test: Pipfile.lock
	pipenv run black --check index.py index_test.py
	pipenv run pytest

up: .env
	pipenv run python -m lambda_gateway index.proxy_request

.PHONY: all clean test up

Pipfile.lock: Pipfile | .venv
	pipenv lock

.venv: Pipfile
	mkdir -p $@
	pipenv install --dev
	touch $@
