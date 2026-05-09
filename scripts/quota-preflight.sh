#!/usr/bin/env bash
set -euo pipefail
REGION="${AWS_REGION:-ap-southeast-1}"
OUT="docs/evidence/00-quota-preflight/quota-check.txt"
mkdir -p "$(dirname "$OUT")"
FAIL=0
{
  echo "=== AWS Quota Pre-flight ($(date -u +%FT%TZ), region=$REGION) ==="
  EKS_LIMIT=$(aws service-quotas get-service-quota --service-code eks --quota-code L-1194D53C --region "$REGION" --query 'Quota.Value' --output text 2>/dev/null || echo "0")
  printf "EKS clusters per region : limit=%s required>=1 : %s\n" "$EKS_LIMIT" "$([ "${EKS_LIMIT%.*}" -ge 1 ] && echo PASS || { echo FAIL; FAIL=1; })"
  VCPU_LIMIT=$(aws service-quotas get-service-quota --service-code ec2 --quota-code L-1216C47A --region "$REGION" --query 'Quota.Value' --output text 2>/dev/null || echo "0")
  printf "On-Demand standard vCPU : limit=%s required>=10 : %s\n" "$VCPU_LIMIT" "$([ "${VCPU_LIMIT%.*}" -ge 10 ] && echo PASS || { echo FAIL; FAIL=1; })"
  VPC_USED=$(aws ec2 describe-vpcs --region "$REGION" --query 'length(Vpcs)' --output text 2>/dev/null || echo "0")
  VPC_LIMIT=$(aws service-quotas get-service-quota --service-code vpc --quota-code L-F678F1CE --region "$REGION" --query 'Quota.Value' --output text 2>/dev/null || echo "0")
  printf "VPCs per region         : used=%s limit=%s required>=1-free : %s\n" "$VPC_USED" "$VPC_LIMIT" "$(awk -v u="$VPC_USED" -v l="$VPC_LIMIT" 'BEGIN{exit !(l-u>=1)}' && echo PASS || { echo FAIL; FAIL=1; })"
  EIP_USED=$(aws ec2 describe-addresses --region "$REGION" --query 'length(Addresses)' --output text 2>/dev/null || echo "0")
  EIP_LIMIT=$(aws service-quotas get-service-quota --service-code ec2 --quota-code L-0263D0A3 --region "$REGION" --query 'Quota.Value' --output text 2>/dev/null || echo "0")
  printf "Elastic IPs             : used=%s limit=%s required>=2-free : %s\n" "$EIP_USED" "$EIP_LIMIT" "$(awk -v u="$EIP_USED" -v l="$EIP_LIMIT" 'BEGIN{exit !(l-u>=2)}' && echo PASS || { echo FAIL; FAIL=1; })"
  NAT_LIMIT=$(aws service-quotas get-service-quota --service-code vpc --quota-code L-FE5A380F --region "$REGION" --query 'Quota.Value' --output text 2>/dev/null || echo "0")
  printf "NAT GW per AZ           : limit=%s required>=1 : %s\n" "$NAT_LIMIT" "$([ "${NAT_LIMIT%.*}" -ge 1 ] && echo PASS || { echo FAIL; FAIL=1; })"
  if [ "$FAIL" -eq 0 ]; then echo "ALL QUOTAS OK"; else echo "QUOTA FAIL — request increase via https://console.aws.amazon.com/servicequotas/"; fi
} | tee "$OUT"
exit $FAIL
