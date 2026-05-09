# Pinned External References (Single Source of Truth)
# This file is the canonical on-disk version-pin manifest for the Max Weather DevOps deliverable.
# All Terraform modules, Helm charts, container images, and CLI tools used by this repository
# commit to the version pins below. T1 (repo scaffolding) authors this file; downstream tasks
# consume from this file as the single source of truth. Never edited manually after T1.

| Component | Version Pin | Source URL |
|-----------|-------------|------------|
| terraform-aws-vpc | v5.13.0 | https://github.com/terraform-aws-modules/terraform-aws-vpc/blob/v5.13.0/main.tf |
| terraform-aws-eks | v20.24.0 | https://github.com/terraform-aws-modules/terraform-aws-eks/blob/v20.24.0/main.tf |
| nginxinc/kubernetes-ingress (chart) | 2.5.1 | https://github.com/nginxinc/kubernetes-ingress/tree/v5.4.1/charts/nginx-ingress |
| nginxinc/kubernetes-ingress (controller) | 5.4.1 | https://hub.docker.com/r/nginx/nginx-ingress |
| aws-jwt-verify | 4.0.1 | https://www.npmjs.com/package/aws-jwt-verify |
| jenkins/jenkins (helm) | 5.5.0 | https://github.com/jenkinsci/helm-charts/tree/jenkins-5.5.0 |
| cluster-autoscaler (helm) | 9.37.0 | https://github.com/kubernetes/autoscaler/tree/cluster-autoscaler-chart-9.37.0 |
| aws-for-fluent-bit (helm) | 0.1.32 | https://github.com/aws/eks-charts/tree/aws-for-fluent-bit-0.1.32 |
| terraform | 1.9.6 | https://releases.hashicorp.com/terraform/1.9.6/ |
| tflint | 0.53.0 | https://github.com/terraform-linters/tflint/releases/tag/v0.53.0 |
| kubeconform | 0.6.7-alpine | https://github.com/yannh/kubeconform/releases/tag/v0.6.7 |
| yq | 4.44.3 | https://github.com/mikefarah/yq/releases/tag/v4.44.3 |
| gh CLI | 2.55.0 | https://github.com/cli/cli/releases/tag/v2.55.0 |
| gitleaks | 8.18.4 | https://github.com/gitleaks/gitleaks/releases/tag/v8.18.4 |
| newman | 6.2.1 | https://www.npmjs.com/package/newman |
| bitnami/kubectl image | 1.30.4 | https://hub.docker.com/r/bitnami/kubectl |
| amazon/aws-cli image | 2.18.7 | https://hub.docker.com/r/amazon/aws-cli |
| node image | 20.18-alpine | https://hub.docker.com/_/node |
| docker:cli image | 24.0.7-cli | https://hub.docker.com/_/docker |
| pipeline-stage-view (Jenkins plugin) | 2.34 | https://plugins.jenkins.io/pipeline-stage-view |
| pipeline-rest-api (Jenkins plugin) | 2.34 | https://plugins.jenkins.io/pipeline-rest-api |
