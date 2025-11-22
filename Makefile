all: build

.PHONY: deps
deps:
	pip install -r requirements-dev.txt

.PHONY: test
test:
	python -m pytest --cov-report html:coverage --cov-report xml:coverage/coverage.xml --cov=workflow_ocr_backend -m "not harp_integration" test

.PHONY: harp-integrationtest
harp-integrationtest:
	python -m pytest -m "harp_integration" test

.PHONY: build
build:
	docker build -t workflow-ocr-backend .