REGION     ?= us-east-1
CLUSTER    ?= max-weather
NAMESPACE  ?= weather-staging
GIT_SHA    := $(shell git rev-parse --short HEAD)
STAGING_DIR := infra/envs/poc

APP_REPO   ?= $(shell cd $(STAGING_DIR) && terraform output -raw weather_api_repository_url 2>/dev/null || echo "PLACEHOLDER_ECR_URL")
ECR_HOST   := $(shell echo $(APP_REPO) | cut -d/ -f1)

.PHONY: help init plan apply destroy \
        ecr-login app-build app-build-push app-run-local app-shell \
        authorizer-package authorizer-deploy \
        install-addons deploy-staging deploy-prod \
        test lint \
        evidence nuke \
        bootstrap postman load-test verify-evidence \
        teardown teardown-force cloud-nuke-dry cloud-nuke-force

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

init: ## Initialize Terraform for staging env
	cd $(STAGING_DIR) && terraform init

plan: ## Plan Terraform changes for staging env
	cd $(STAGING_DIR) && terraform plan

apply: ## Apply Terraform changes for staging env
	cd $(STAGING_DIR) && terraform apply -auto-approve

destroy: ## Destroy Terraform infrastructure for staging env
	cd $(STAGING_DIR) && terraform destroy -auto-approve

ecr-login: ## Authenticate Docker to ECR
	aws ecr get-login-password --region $(REGION) | docker login --username AWS --password-stdin $(ECR_HOST)

app-build: ## Build weather-api Docker image locally
	docker buildx build --platform linux/amd64 -t weather-api:$(GIT_SHA) app/

app-build-push: ecr-login ## Build and push weather-api image to ECR
	docker buildx build --platform linux/amd64 \
		-t $(APP_REPO):$(GIT_SHA) \
		--push app/

app-run-local: ## Run weather-api locally
	docker run --rm -p 8080:8080 weather-api:$(GIT_SHA)

app-shell: ## Shell into weather-api container
	docker run --rm -it --entrypoint sh weather-api:$(GIT_SHA)

authorizer-package: ## Package Lambda authorizer ZIP
	cd lambda-authorizer && rm -rf node_modules
	cd lambda-authorizer && npm ci --omit=dev
	mkdir -p dist
	cd lambda-authorizer && zip -qr ../dist/lambda-authorizer.zip src/ node_modules/ package.json

authorizer-deploy: authorizer-package ## Deploy Lambda authorizer ZIP to AWS
	aws lambda update-function-code \
		--function-name max-weather-authorizer \
		--zip-file fileb://dist/lambda-authorizer.zip \
		--region $(REGION)
	aws lambda wait function-updated \
		--function-name max-weather-authorizer \
		--region $(REGION)

install-addons: ## Install/upgrade all cluster Helm add-ons (idempotent)
	CLUSTER_NAME=$(CLUSTER) AWS_REGION=$(REGION) bash scripts/install-helm-addons.sh

# MANUAL OVERRIDE — production deploys go through Jenkins max-weather-deploy job
deploy-staging: install-addons ## Install add-ons then deploy to staging via kubectl kustomize
	aws eks update-kubeconfig --name $(CLUSTER) --region $(REGION)
	kubectl apply -k k8s/overlays/staging
	kubectl rollout status deployment/weather-api -n $(NAMESPACE) --timeout=180s

# MANUAL OVERRIDE — production deploys go through Jenkins max-weather-deploy job
deploy-prod: ## Deploy to prod via kubectl kustomize
	aws eks update-kubeconfig --name $(CLUSTER) --region $(REGION)
	kubectl apply -k k8s/overlays/prod
	kubectl rollout status deployment/weather-api -n weather-prod --timeout=180s

test: ## Run all tests (app + authorizer)
	cd app && npm ci && npm test
	cd lambda-authorizer && npm ci && npm test

lint: ## Lint application code
	cd app && npm run lint

evidence: ## Collect evidence artifacts into docs/evidence/
	@mkdir -p docs/evidence/01-terraform docs/evidence/02-eks-nodes \
		docs/evidence/03-cloudwatch-logs docs/evidence/04-hpa-scaling \
		docs/evidence/05-api-gateway docs/evidence/06-postman \
		docs/evidence/07-jenkins docs/evidence/08-teardown
	@echo "Evidence dirs ready — run scripts/collect-evidence.sh for full collection"

nuke: ## DANGER: Destroy all infrastructure using cloud-nuke
	scripts/teardown.sh

bootstrap: ## Initialize Terraform state backend (S3 + DynamoDB)
	cd infra/bootstrap && terraform init && terraform apply -auto-approve

postman: ## Run Postman collection via Newman against staging
	bash scripts/run-postman.sh

load-test: ## Run k6 load test with HPA evidence capture
	bash scripts/run-loadtest.sh

verify-evidence: ## Verify all evidence files are present
	bash scripts/verify-evidence.sh

teardown: ## Ordered teardown of all infrastructure (interactive)
	bash scripts/teardown.sh

teardown-force: ## Teardown without interactive prompt (CI use only)
	@echo "destroy max-weather" | bash scripts/teardown.sh

cloud-nuke-dry: ## Dry-run cloud-nuke to find orphaned resources
	bash scripts/cloud-nuke-wrapper.sh --dry-run

cloud-nuke-force: ## DANGER: Force cloud-nuke all max-weather resources
	bash scripts/cloud-nuke-wrapper.sh --force
