.PHONY: help init plan apply destroy build push deploy-staging deploy-prod test evidence nuke

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

init: ## Initialize Terraform (all modules)
	@echo "TODO: implement in later waves"

plan: ## Plan Terraform changes
	@echo "TODO: implement in later waves"

apply: ## Apply Terraform changes
	@echo "TODO: implement in later waves"

destroy: ## Destroy Terraform infrastructure
	@echo "TODO: implement in later waves"

build: ## Build application and containers
	@echo "TODO: implement in later waves"

push: ## Push container images to registry
	@echo "TODO: implement in later waves"

deploy-staging: ## Deploy to staging environment
	@echo "TODO: implement in later waves"

deploy-prod: ## Deploy to production environment
	@echo "TODO: implement in later waves"

test: ## Run all tests
	@echo "TODO: implement in later waves"

evidence: ## Generate evidence artifacts
	@echo "TODO: implement in later waves"

nuke: ## Destroy all infrastructure and clean up
	@echo "TODO: implement in later waves"
