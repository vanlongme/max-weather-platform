# CI/CD Setup Guide

## Jenkins Pipeline

The `Jenkinsfile` at the repository root implements a declarative pipeline:

```
Checkout → App Lint+Test → Authorizer Test → Build+Push → Update Kustomize → Deploy → Smoke Test
```

## Required Jenkins Plugins

Install the following plugins via **Manage Jenkins → Plugin Manager**:

| Plugin | Purpose |
|---|---|
| Pipeline | Declarative pipeline support |
| Git | Checkout from repository |
| Docker Pipeline | `docker` DSL steps |
| AnsiColor | Colorized terminal output |
| Timestamper | Timestamps in console |
| JUnit | Test result publishing |

## Initial Jenkins Setup

1. Navigate to `http://<JENKINS_EIP>:8080`
2. Unlock with: `cat /home/ubuntu/initialAdminPassword` (on Jenkins EC2)
3. Install suggested plugins
4. Create an admin user
5. Install the required plugins listed above

## Creating the Pipeline Job

1. **New Item** → **Pipeline** → Name: `max-weather-staging`
2. **Definition**: Pipeline script from SCM
3. **SCM**: Git, repository URL, branch `main`
4. **Script Path**: `Jenkinsfile`
5. Save and run **Build Now**

## Required Tools on Jenkins Agent

The `user-data.sh` bootstrap script installs:
- Docker (for buildx)
- kubectl 1.30
- Helm 3
- AWS CLI v2

## AWS Access

Jenkins uses an **IAM instance profile** — no static credentials needed. The instance profile role (`max-weather-jenkins`) has permissions for:
- ECR (push images)
- EKS (update kubeconfig, deploy)
- Lambda (update function code)

## Environment Variables Used by Pipeline

| Variable | Source | Description |
|---|---|---|
| `AWS_REGION` | Jenkinsfile | AWS region |
| `CLUSTER` | Jenkinsfile | EKS cluster name |
| `NAMESPACE` | Jenkinsfile | Deploy namespace |
| `GIT_SHA` | Git | Short commit SHA for image tag |
| `APP_REPO` | Terraform output | ECR repository URL |
