#!/usr/bin/env bash
# install-helm-addons.sh
# Installs/upgrades all cluster add-ons via Helm using values from k8s/helm/.
# Idempotent: safe to re-run; Helm computes diffs and applies the patch.
#
# Required env (auto-discovered from terraform output if not set):
#   CLUSTER_NAME, AWS_REGION
#
# Required tools: helm 3.13+, kubectl 1.29+, aws CLI v2, jq, envsubst
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly HELM_DIR="${REPO_ROOT}/k8s/helm"
readonly STAGING_DIR="${REPO_ROOT}/infra/envs/poc"

CLUSTER_NAME="${CLUSTER_NAME:-max-weather}"
AWS_REGION="${AWS_REGION:-us-east-1}"
HELM_TIMEOUT="${HELM_TIMEOUT:-5m}"

log() { printf '[install-helm-addons] %s\n' "$*"; }
die() { printf '[install-helm-addons] ERROR: %s\n' "$*" >&2; exit 1; }

require() { command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"; }
require helm
require kubectl
require aws
require jq
require envsubst

# Pull terraform outputs once into a JSON blob.
log "Reading terraform outputs from ${STAGING_DIR}"
if [[ ! -d "${STAGING_DIR}/.terraform" ]]; then
  die "terraform not initialized in ${STAGING_DIR}; run 'make init && make apply' first"
fi
TF_OUTPUTS_JSON="$(cd "${STAGING_DIR}" && terraform output -json 2>/dev/null)"
[[ -n "${TF_OUTPUTS_JSON}" && "${TF_OUTPUTS_JSON}" != "{}" ]] || die "terraform output is empty; run 'make apply' first"

tf_out() {
  # Read a top-level terraform output value (string).
  local key="$1"
  local val
  val="$(jq -r --arg k "$key" '.[$k].value // empty' <<<"${TF_OUTPUTS_JSON}")"
  [[ -n "${val}" ]] || die "terraform output '${key}' is empty (expected after 'make apply')"
  printf '%s' "${val}"
}

# Resolve variables for envsubst. Exported so envsubst sees them.
export CLUSTER_NAME AWS_REGION
export VPC_ID="$(tf_out vpc_id)"
export CLUSTER_ENDPOINT="$(tf_out cluster_endpoint)"
export LOG_GROUP_NAME="$(tf_out eks_application_log_group)"
export CLUSTER_AUTOSCALER_ROLE_ARN="$(tf_out cluster_autoscaler_role_arn)"
export FLUENT_BIT_ROLE_ARN="$(tf_out fluent_bit_role_arn)"
export AWS_LB_CONTROLLER_ROLE_ARN="$(tf_out aws_lb_controller_role_arn)"
export EXTERNAL_SECRETS_ROLE_ARN="$(tf_out external_secrets_role_arn)"
export KARPENTER_IAM_ROLE_ARN="$(tf_out karpenter_iam_role_arn)"
export KARPENTER_QUEUE_NAME="$(tf_out karpenter_queue_name)"
export KARPENTER_NODE_IAM_ROLE_NAME="$(tf_out karpenter_node_iam_role_name)"
export JENKINS_IRSA_ROLE_ARN="$(tf_out jenkins_role_arn)"

# Ensure kubeconfig points at the cluster.
log "Updating kubeconfig for ${CLUSTER_NAME} in ${AWS_REGION}"
aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}" >/dev/null

# Add Helm repos (idempotent).
log "Adding Helm repositories"
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null
helm repo add autoscaler https://kubernetes.github.io/autoscaler >/dev/null
helm repo add eks https://aws.github.io/eks-charts >/dev/null
helm repo add external-secrets https://charts.external-secrets.io >/dev/null
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ >/dev/null
helm repo add jenkinsci https://charts.jenkins.io >/dev/null
helm repo update >/dev/null

# Render a values file with envsubst into a temp file.
render_values() {
  local src="$1"
  local dst
  dst="$(mktemp)"
  envsubst <"${src}" >"${dst}"
  printf '%s' "${dst}"
}

helm_install() {
  local release="$1" chart="$2" version="$3" namespace="$4" values_file="$5" create_ns="${6:-true}"
  local rendered
  rendered="$(render_values "${values_file}")"
  local create_ns_flag=""
  [[ "${create_ns}" == "true" ]] && create_ns_flag="--create-namespace"

  log "helm upgrade --install ${release} (${chart} ${version}) -> ${namespace}"
  # shellcheck disable=SC2086
  helm upgrade --install "${release}" "${chart}" \
    --version "${version}" \
    --namespace "${namespace}" \
    ${create_ns_flag} \
    --values "${rendered}" \
    --timeout "${HELM_TIMEOUT}" \
    --wait
  rm -f "${rendered}"
}

# 1. metrics-server first (no IRSA, dependency for HPA used by everything else)
helm_install metrics-server metrics-server/metrics-server 3.12.1 \
  kube-system "${HELM_DIR}/metrics-server/values.yaml" false

# 2. cluster-autoscaler
helm_install cluster-autoscaler autoscaler/cluster-autoscaler 9.37.0 \
  kube-system "${HELM_DIR}/cluster-autoscaler/values.yaml" false

# 3. aws-load-balancer-controller (needed before nginx-ingress provisions NLB)
helm_install aws-load-balancer-controller eks/aws-load-balancer-controller 1.8.2 \
  kube-system "${HELM_DIR}/aws-lb-controller/values.yaml" false

# 4. nginx-ingress (provisions the public NLB via aws-load-balancer-controller annotations)
helm_install nginx-ingress ingress-nginx/ingress-nginx 4.11.3 \
  ingress-nginx "${HELM_DIR}/nginx-ingress/values.yaml" true

# 5. fluent-bit (CloudWatch Logs sink)
helm_install aws-for-fluent-bit eks/aws-for-fluent-bit 0.1.34 \
  amazon-cloudwatch "${HELM_DIR}/fluent-bit/values.yaml" true

# 6. external-secrets (CRDs + controller)
helm_install external-secrets external-secrets/external-secrets 0.10.4 \
  external-secrets "${HELM_DIR}/external-secrets/values.yaml" true

# Apply ClusterSecretStore CR after the external-secrets controller is healthy.
log "Applying ClusterSecretStore (aws-secretsmanager)"
css_rendered="$(render_values "${HELM_DIR}/external-secrets/cluster-secret-store.yaml")"
kubectl apply -f "${css_rendered}"
rm -f "${css_rendered}"

# 7. karpenter (OCI chart from public ECR; must be installed AFTER cluster-autoscaler
#    so the default managed node group exists for the controller pods to land on).
log "helm upgrade --install karpenter (oci://public.ecr.aws/karpenter/karpenter 1.6.0) -> kube-system"
karpenter_rendered="$(render_values "${HELM_DIR}/karpenter/values.yaml")"
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version 1.6.0 \
  --namespace kube-system \
  --values "${karpenter_rendered}" \
  --timeout "${HELM_TIMEOUT}" \
  --wait
rm -f "${karpenter_rendered}"

# Apply EC2NodeClass + NodePool after the controller is healthy (CRDs are bundled in the chart).
log "Applying Karpenter EC2NodeClass and NodePool"
ec2nc_rendered="$(render_values "${HELM_DIR}/karpenter/ec2nodeclass.yaml")"
np_rendered="$(render_values "${HELM_DIR}/karpenter/nodepool.yaml")"
kubectl apply -f "${ec2nc_rendered}"
kubectl apply -f "${np_rendered}"
rm -f "${ec2nc_rendered}" "${np_rendered}"

# 8. Application namespaces (replaces the deleted infra/modules/namespaces TF
#    module). Applied AFTER ingress-nginx so the NetworkPolicy that allows
#    traffic from the ingress-nginx namespace can resolve its target.
log "Applying application namespaces (weather-staging, weather-prod)"
kubectl apply -f "${REPO_ROOT}/k8s/manifests/namespaces.yaml"

# 9. Jenkins (replaces the deleted infra/modules/jenkins EC2-based TF module).
#    Chart version: latest at install time unless JENKINS_CHART_VERSION is set.
JENKINS_CHART_VERSION="${JENKINS_CHART_VERSION:-$(helm search repo jenkinsci/jenkins --output json | jq -r '.[0].version')}"
[[ -n "${JENKINS_CHART_VERSION}" && "${JENKINS_CHART_VERSION}" != "null" ]] \
  || die "could not resolve jenkinsci/jenkins chart version (helm search returned empty)"
log "Resolved jenkinsci/jenkins chart version: ${JENKINS_CHART_VERSION}"
helm_install jenkins jenkinsci/jenkins "${JENKINS_CHART_VERSION}" \
  jenkins "${HELM_DIR}/jenkins/values.yaml" true

log "All cluster add-ons installed successfully."
helm ls -A | grep -E '(NAME|nginx-ingress|cluster-autoscaler|aws-load-balancer-controller|aws-for-fluent-bit|external-secrets|metrics-server|karpenter|jenkins)' || true
