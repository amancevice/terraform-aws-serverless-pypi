all: test

clean:
	pipenv --rm

test: Pipfile.lock
	pipenv run ruff check index*.py
	pipenv run pytest

up: .env
	pipenv run python -m lambda_gateway index.proxy_request

.PHONY: all clean test up

Pipfile.lock: Pipfile | .venv
	pipenv lock

.venv: .python-version Pipfile
	-pipenv --rm
	mkdir -p $@
	pipenv install --dev
	touch $@
