all: build

.PHONY: deps
deps:
	pip install -r requirements-dev.txt

.PHONY: test
test:
	python -m pytest --cov-report html:coverage --cov-report xml:coverage/coverage.xml --cov=workflow_ocr_backend -m "not docker_integration" test

.PHONY: docker-integrationtest
docker-integrationtest:
	python -m pytest -m "docker_integration" test

.PHONY: build
build:
	docker build -t workflow-ocr-backend .