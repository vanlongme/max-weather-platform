.PHONY: help preflight apply destroy validate lint test evidence gitleaks

REGION ?= ap-southeast-1
TF_DIR = terraform/envs/staging

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

preflight: ## Run AWS quota pre-flight checks
	bash scripts/quota-preflight.sh

apply: ## Apply Terraform (staging env)
	cd $(TF_DIR) && terraform init && terraform apply -auto-approve

destroy: ## Destroy all Terraform infrastructure + cleanup
	@echo "=== Tear-down sequence ==="
	@if [ -f scripts/apigw-setup.sh ] && [ -f docs/evidence/12-api-gateway/api-id.txt ]; then \
	  API_ID=$$(cat docs/evidence/12-api-gateway/api-id.txt); \
	  aws apigateway delete-rest-api --rest-api-id $$API_ID --region $(REGION) 2>/dev/null || true; \
	fi
	cd $(TF_DIR) && terraform destroy -auto-approve
	@echo "=== Post-destroy verification ==="
	aws eks list-clusters --region $(REGION) --output text

validate: ## Validate Terraform modules
	cd terraform/envs/staging && terraform init -backend=false && terraform validate
	cd terraform/envs/bootstrap && terraform init -backend=false && terraform validate

lint: ## Run tflint
	@command -v tflint || (curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash)
	tflint --chdir=terraform/envs/staging

test: ## Run all tests (app + lambda)
	cd app && npm test
	cd lambda-authorizer && npm test

evidence: ## Show evidence directory tree
	find docs/evidence -maxdepth 2 | sort

gitleaks: ## Scan for secrets
	@command -v gitleaks || (curl -sSfL https://github.com/gitleaks/gitleaks/releases/download/v8.18.4/gitleaks_8.18.4_linux_x64.tar.gz | tar -xz -C /usr/local/bin gitleaks 2>/dev/null || curl -sSfL https://github.com/gitleaks/gitleaks/releases/download/v8.18.4/gitleaks_8.18.4_linux_x64.tar.gz | tar -xz -C ./bin gitleaks)
	gitleaks detect --source . --no-git
