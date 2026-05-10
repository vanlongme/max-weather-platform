#!/usr/bin/env bash
# Build + publish the max-weather Node.js base image with Chainguard apko.
#
# Usage:
#   AWS_REGION=us-east-1 CLUSTER=max-weather ./build.sh           # build + push :YYYYMMDD + :latest tags
#   ./build.sh local                                              # build a local OCI tarball only (no push)
#
# Requires: apko (https://github.com/chainguard-dev/apko), docker (for ECR login + push).
set -euo pipefail

cd "$(dirname "$0")"

AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER="${CLUSTER:-max-weather}"
TAG="${TAG:-$(date -u +%Y%m%d)}"

if [[ "${1:-}" == "local" ]]; then
  echo "Building local OCI tarball at ./base-image.tar (no push)..."
  apko build apko.yaml "${CLUSTER}-base-nodejs:${TAG}" base-image.tar
  echo "Done. Load with: docker load < base-image.tar"
  exit 0
fi

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REPO="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${CLUSTER}-base-nodejs"

aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# apko publish builds the image and pushes it (multi-tag) to the registry in one step.
apko publish apko.yaml "${REPO}:${TAG}" "${REPO}:latest"

echo "Published ${REPO}:${TAG} and ${REPO}:latest"
