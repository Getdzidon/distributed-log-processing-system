# Makefile for Distributed Log Processing System

.PHONY: help install test lint build deploy clean

help:
	@echo "Distributed Log Processor - Available Commands"
	@echo "======================================="
	@echo "install    - Install dependencies"
	@echo "test       - Run tests with coverage"
	@echo "lint       - Run linters"
	@echo "build      - Build Docker image"
	@echo "deploy     - Deploy to Kubernetes"
	@echo "clean      - Clean build artifacts"

install:
	pip install -r requirements.txt

test:
	pytest tests/ -v --cov=src --cov-report=term --cov-report=html

lint:
	pylint src/ --disable=C0111,R0903
	black --check src/

format:
	black src/ tests/

build:
	docker build -t log-processor:latest .

deploy-staging:
	helm upgrade --install log-processor \
		infrastructure/helm/log-processor \
		--namespace log-processing \
		--create-namespace \
		--values infrastructure/helm/log-processor/values-staging.yaml

deploy-production:
	helm upgrade --install log-processor \
		infrastructure/helm/log-processor \
		--namespace log-processing \
		--create-namespace \
		--values infrastructure/helm/log-processor/values-production.yaml

clean:
	find . -type d -name __pycache__ -exec rm -rf {} +
	find . -type f -name "*.pyc" -delete
	rm -rf .pytest_cache htmlcov .coverage
