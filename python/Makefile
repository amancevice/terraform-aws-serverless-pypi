all: test

clean:
	rm -rf .venv

test: | .venv
	pipenv run black --check index.py index_test.py
	pipenv run pytest

up: .env
	pipenv run python -m lambda_gateway index.proxy_request

.PHONY: all clean test up

.venv: Pipfile
	mkdir $@
	pipenv install --dev
