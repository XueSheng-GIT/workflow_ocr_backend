all: build

.PHONY: deps
deps:
	pip install -r requirements-dev.txt

.PHONY: test
test:
	python -m pytest --cov-report html:coverage --cov-report xml:coverage/coverage.xml --cov=workflow_ocr_backend test

.PHONY: build
build:
	docker build -t workflow-ocr-backend .