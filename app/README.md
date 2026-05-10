# weather-api

Express service proxying Open-Meteo. Built on the
[Chainguard apko base image](../base-image/README.md) and deployed to EKS by the
declarative pipeline in [`Jenkinsfile`](./Jenkinsfile).

## Local dev

```bash
npm ci
npm run dev          # node --watch src/server.js on :8080
npm test             # jest + supertest, with coverage
npm run lint         # eslint
```

## Container build

```bash
make app-build       # local image weather-api:<sha> using cgr.dev/chainguard/node:latest
make app-build-push  # build + push <ecr>/<cluster>-api:staging-<sha> + :latest
```

The Dockerfile parameterises the base image via `--build-arg BASE_IMAGE=` so CI
can swap to the in-account ECR copy of the apko-built base
(`<cluster>-base-nodejs:latest`) for supply-chain isolation.

## Jenkins pipeline

`Jenkinsfile` (declarative) stages:

```
Checkout → App Lint+Test → Authorizer Test → Base Image (apko, conditional)
       → Build+Push App → Update Kustomize → Install Addons → Deploy → Smoke
```

### Required Jenkins plugins

| Plugin | Purpose |
|---|---|
| Pipeline | Declarative pipeline support |
| Git | Checkout from repository |
| Docker Pipeline | `docker` DSL steps |
| AnsiColor | Colorized console output |
| Timestamper | Timestamps in console |
| JUnit | Test result publishing |

### Job setup

1. **New Item** → **Pipeline** → name `max-weather-staging`
2. **Definition**: Pipeline script from SCM
3. **SCM**: Git, branch `main`
4. **Script Path**: `app/Jenkinsfile`
5. Save → **Build Now**

### IAM

The Jenkins controller pod runs with the `jenkins` IRSA role (created by
`infra/modules/iam`) and is granted Edit on `weather-staging` + `weather-prod`
via the EKS access entry registered in the `eks` module. ECR push, EKS
`update-kubeconfig`, and Lambda `update-function-code` permissions all flow
through that single role — no static credentials.

### Pipeline environment variables

| Variable | Source | Description |
|---|---|---|
| `AWS_REGION` | Jenkinsfile | AWS region (`us-east-1`) |
| `CLUSTER` | Jenkinsfile | EKS cluster name (`max-weather`) |
| `NAMESPACE` | Jenkinsfile | Deploy namespace (`weather-staging`) |
| `GIT_SHA` | git | Short commit SHA — image tag |
| `APP_REPO` | terraform output | ECR repository URL for the app |
| `ECR_HOST` | derived from `APP_REPO` | Registry host for `docker login` |
