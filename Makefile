SHELL       := /bin/bash

REGION      ?= us-east-1
CLUSTER     ?= poc-max-weather-cluster
NAMESPACE   ?= weather-staging
GIT_SHA     := $(shell git rev-parse --short HEAD)
STAGING_DIR := infra/envs/poc

APP_REPO    ?= $(shell cd $(STAGING_DIR) && terraform output -raw ecr_api_repository_url 2>/dev/null || echo "PLACEHOLDER_ECR_URL")
ECR_HOST    := $(shell echo $(APP_REPO) | cut -d/ -f1)

# Staged apply targets — required because terraform-aws-modules/eks v21
# uses unknown-at-plan counts in the node-group submodule, and
# kubernetes_manifest / helm_release resources need a live cluster API at
# plan time. Single `terraform apply` cannot bootstrap from zero.
APPLY_STAGE1_TARGETS := \
	-target=module.networking \
	-target=module.cloudwatch \
	-target=module.ecr \
	-target=module.secrets \
	-target=module.iam

APPLY_STAGE2_TARGETS := \
	-target=module.eks \
	-target=module.lambda

APPLY_STAGE3A_TARGETS := \
	-target=module.eks_self_managed_addons.helm_release.ingress_nginx \
	-target=module.eks_self_managed_addons.helm_release.cluster_autoscaler \
	-target=module.eks_self_managed_addons.helm_release.fluent_bit \
	-target=module.eks_self_managed_addons.helm_release.external_secrets \
	-target=module.eks_self_managed_addons.helm_release.metrics_server \
	-target=module.eks_self_managed_addons.helm_release.karpenter \
	-target=module.eks_self_managed_addons.helm_release.jenkins \
	-target=module.eks_self_managed_addons.helm_release.keda \
	-target=module.api_gateway

.PHONY: help init plan apply apply-stage1 apply-stage2 apply-stage3 apply-stage3a apply-stage3b apply-all kubeconfig destroy bootstrap \
        ecr-login app-build app-build-push app-run-local app-shell \
        lambda-deps issue-token \
        deploy-staging deploy-prod \
        test lint \
        teardown teardown-force

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

bootstrap: ## Initialize Terraform state backend (S3 + DynamoDB)
	cd infra/bootstrap && terraform init && terraform apply -auto-approve

init: ## Initialize Terraform for staging env
	cd $(STAGING_DIR) && terraform init

plan: ## Plan Terraform changes for staging env (may fail on first run — see apply-all)
	cd $(STAGING_DIR) && terraform plan

apply-stage1: ## [1/3] Apply foundation: VPC, IAM, ECR, Secrets, CloudWatch
	cd $(STAGING_DIR) && terraform apply -auto-approve $(APPLY_STAGE1_TARGETS)

apply-stage2: ## [2/3] Apply EKS cluster + Lambda (depends on stage1)
	cd $(STAGING_DIR) && terraform apply -auto-approve $(APPLY_STAGE2_TARGETS)
	$(MAKE) kubeconfig

apply-stage3a: ## [3a/4] Apply Helm releases + API Gateway (CRDs installed by EKS addons; kubernetes_manifest excluded)
	cd $(STAGING_DIR) && terraform apply -auto-approve $(APPLY_STAGE3A_TARGETS)

apply-stage3b: ## [3b/4] Full apply — kubernetes_manifest resources now succeed (CRDs available)
	cd $(STAGING_DIR) && terraform apply -auto-approve

apply-stage3: apply-stage3a apply-stage3b ## [3/3] Full stage3: helm releases then manifests (two-pass for CRD bootstrap)

apply-all: lambda-deps apply-stage1 apply-stage2 apply-stage3 ## Full staged apply: stage1 → stage2 → kubeconfig → stage3a → stage3b (~25 min from zero)

apply: apply-all ## Alias for apply-all (full staged apply from zero)

kubeconfig: ## Update local kubeconfig for the EKS cluster
	aws eks update-kubeconfig --name $(CLUSTER) --region $(REGION)

destroy: ## Destroy Terraform infrastructure for staging env (prefer `make teardown`)
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

lambda-deps: ## Install Lambda authorizer production deps (required before terraform plan/apply)
	cd infra/envs/poc/lambdas/authorizer && npm ci --omit=dev

issue-token: ## Issue a short-lived HS256 JWT for API testing (reads secret from Secrets Manager)
	@bash scripts/issue-token.sh

deploy-staging: kubeconfig ## Deploy to staging via kubectl kustomize (addons are Terraform-managed)
	kubectl apply -k k8s/overlays/staging
	kubectl rollout status deployment/weather-api -n $(NAMESPACE) --timeout=180s

deploy-prod: kubeconfig ## Deploy to prod via kubectl kustomize (addons are Terraform-managed)
	kubectl apply -k k8s/overlays/prod
	kubectl rollout status deployment/weather-api -n weather-prod --timeout=180s

test: ## Run app tests
	cd app && npm ci && npm test

lint: ## Lint application code
	cd app && npm run lint

teardown: ## Ordered teardown — terraform destroy (workload + bootstrap), then cloud-nuke orphan sweep (interactive)
	bash scripts/teardown.sh

teardown-force: ## Ordered teardown without interactive prompt (CI use only)
	TEARDOWN_FORCE=1 bash scripts/teardown.sh
