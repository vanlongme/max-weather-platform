# Private Cluster Bring-up Runbook

Max Weather — POC environment. Hybrid-endpoint EKS cluster (private workloads, operator access
via IP allowlist). Follows the staged apply sequence mandatory for `terraform-aws-modules/eks` v21.

Region: **us-east-1** (only region currently supported).

---

## Prerequisites

### AWS account

- Admin IAM credentials configured (`aws configure` or environment variables).
- No pre-existing `max-weather` resources in the account (run `make teardown-force` first if unsure).

### Tools

| Tool | Minimum version |
|------|----------------|
| GNU Make | any recent |
| Terraform | 1.6+ |
| kubectl | 1.29+ |
| Helm | 3.13+ |
| Docker (buildx) | 24+ |
| Node.js | 20+ |
| AWS CLI v2 | 2.x |
| newman (optional) | any — for Postman collection runs |

Install `newman` via `npm i -g newman`.

### Operator IP CIDR

The EKS public endpoint rejects requests from any IP not in the allowlist. You must know your
outbound IP before applying.

```bash
curl -s ifconfig.me
# Example output: 203.0.113.45
```

You will set `endpoint_public_access_cidrs = ["YOUR_OPERATOR_IP/32"]` in `terraform.tfvars`
(step 3 of Bring-up below). Replace `YOUR_OPERATOR_IP` with the IP returned above.

---

## Bring-up

Steps are idempotent. Each stage must succeed before the next starts.

### Step 1 — optional clean slate

If a prior environment exists:

```bash
make teardown-force   # CI-safe; no confirmation prompt
```

Skip if starting from a fresh account.

### Step 2 — bootstrap remote state

```bash
make bootstrap
```

Creates S3 bucket (`max-weather-tfstate-<ACCOUNT_ID>`) and DynamoDB lock table
(`max-weather-tflock`). Safe to re-run; Terraform skips already-existing resources.
Run once per AWS account. Do not destroy bootstrap resources between deploys.

### Step 3 — set operator IP allowlist

Edit `infra/envs/poc/terraform.tfvars`:

```hcl
endpoint_public_access_cidrs = ["YOUR_OPERATOR_IP/32"]
```

Replace `YOUR_OPERATOR_IP` with the IP from `curl ifconfig.me`. The validation block rejects
`0.0.0.0/0`.

### Step 4 — install Lambda authorizer dependencies

```bash
make lambda-deps
```

Runs `npm ci --omit=dev` in `infra/envs/poc/lambdas/authorizer/`. This is **required** before
any `terraform plan` or `terraform apply` because `archive_file` zips the directory at plan
time. Skipping this step causes a plan-time error.

### Step 5 — init

```bash
make init
```

Downloads providers and modules. Uses the remote S3 backend created in step 2.

### Step 6 — staged apply (~25 min from zero)

```bash
make apply-all
```

Chains three stages internally. Do not attempt a single `terraform apply` from zero — it fails
because `terraform-aws-modules/eks` v21 uses unknown-at-plan counts inside its node-group
submodule, and the `helm_release` / `kubernetes_manifest` providers need a live cluster API at
plan time.

The three stages:

| Stage | Targets | What it creates |
|-------|---------|-----------------|
| stage1 | networking, cloudwatch, ecr, secrets, iam | VPC, subnets, NAT GW, 17 VPCEs, ECR, IAM, Secrets Manager |
| stage2 | eks, lambda | EKS control plane + node groups, updates kubeconfig, Lambda authorizer |
| stage3 | all remaining (two-pass) | Helm releases (ingress-nginx, Karpenter, KEDA, Jenkins, ...), API Gateway + VPC Link, Karpenter NodePool |

If a stage fails, fix the error and re-run the failing stage independently
(`make apply-stage1`, `make apply-stage2`, or `make apply-stage3`). Each stage is idempotent.

> **API Gateway note**: API GW + VPC Link are fully Terraform-managed via
> `infra/modules/api_gateway/`. There is no `scripts/api-gw-setup.sh` and no `make api-gw-setup`
> target. References to that script in older documentation are obsolete.

### Step 7 — build and push application image

```bash
make app-build-push
```

Authenticates to ECR, builds `app/` with Docker buildx (linux/amd64), and pushes with the
current git short SHA as the image tag. The `latest` tag is never used.

### Step 8 — deploy workload

```bash
make deploy-staging
```

Applies `k8s/overlays/staging` via `kubectl apply -k` and waits for rollout to complete
(180 s timeout).

---

## Validation

Run these commands after a successful bring-up. Each command shows the expected output.

### 1. Endpoint posture

```bash
aws eks describe-cluster --name poc-max-weather-cluster \
  --query 'cluster.resourcesVpcConfig.{priv:endpointPrivateAccess,pub:endpointPublicAccess,cidrs:publicAccessCidrs}'
```

Expected: `priv=true`, `pub=true`, `cidrs=["YOUR_OPERATOR_IP/32"]`.

### 2. Control plane logging

```bash
aws eks describe-cluster --name poc-max-weather-cluster \
  --query 'cluster.logging.clusterLogging[?enabled==`true`].types[]'
```

Expected: `["api", "audit", "authenticator", "controllerManager", "scheduler"]`

### 3. KMS envelope encryption

```bash
aws eks describe-cluster --name poc-max-weather-cluster \
  --query 'cluster.encryptionConfig[].{r:resources,k:provider.keyArn}'
```

Expected: `resources=["secrets"]`, `keyArn` contains `alias/poc-max-weather-cluster-key`.

### 4. VPC endpoints available

```bash
aws ec2 describe-vpc-endpoints \
  --filters Name=vpc-id,Values=$(cd infra/envs/poc && terraform output -raw vpc_id) \
  --query 'VpcEndpoints[].{svc:ServiceName,state:State}'
```

Expected: 17 entries, all `State=available` (16 interface + 1 S3 gateway).

### 5. IMDSv2 enforced on MNG instances

```bash
aws ec2 describe-instances \
  --filters "Name=tag:eks:cluster-name,Values=poc-max-weather-cluster" \
  --query 'Reservations[].Instances[].MetadataOptions.{tok:HttpTokens,hop:HttpPutResponseHopLimit}'
```

Expected: all `HttpTokens=required`. MNG nodes have `hop=1`; Karpenter nodes have `hop=2`
(Pod Identity Agent requires 2).

### 6. Internal NLB scheme

```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.metadata.annotations.service\.beta\.kubernetes\.io/aws-load-balancer-scheme}'
```

Expected: `internal`

Verify AWS reality (K8s annotation alone is not authoritative):

```bash
aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?contains(LoadBalancerName, `a`)].{name:LoadBalancerName,scheme:Scheme}'
```

Expected: `scheme=internal` for the ingress-nginx NLB.

### 7. Workload on private subnets

```bash
kubectl get pod -n weather-api -o wide | head -5
```

Cross-reference the node's zone:

```bash
kubectl get node <node-name> \
  -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}'
```

Nodes should run in private subnets (no public IPs on the EC2 instances).

### 8. End-to-end API test

```bash
TOKEN=$(bash scripts/issue-token.sh --env staging)
API_URL=$(cd infra/envs/poc && terraform output -raw api_gateway_invoke_url_staging)
curl -sS -H "Authorization: Bearer ${TOKEN}" \
  "${API_URL}/weather?latitude=37&longitude=-122" | jq .
```

Expected: HTTP 200, JSON body with current weather fields (temperature, wind speed, etc.).

> Use `bash scripts/issue-token.sh --env staging` directly. `make issue-token` does not forward
> the `--env` flag and will exit 2.

### 9. Terraform clean state

```bash
terraform -chdir=infra/envs/poc fmt -recursive -check
terraform -chdir=infra/envs/poc validate
terraform -chdir=infra/envs/poc/eks-self-managed-addons fmt -check
terraform -chdir=infra/envs/poc/eks-self-managed-addons validate
```

Expected: no diff output, `Success! The configuration is valid.`

---

## Operator kubectl access

### Path A — public endpoint via allowlist (recommended)

Works immediately after `make apply-all` or `make apply-stage2`.

```bash
aws eks update-kubeconfig --region us-east-1 --name poc-max-weather-cluster
kubectl get nodes
```

`kubectl get nodes` succeeds only from the IP in `endpoint_public_access_cidrs`. If your IP has
changed since apply, see Path C.

### Path B — SSM Session Manager + port-forward (no allowlist change needed)

Use when your IP changed or you can't edit tfvars.

1. Find an infra MNG instance (controller nodes on public subnets):

   ```bash
   aws ec2 describe-instances \
     --filters "Name=tag:eks:nodegroup-name,Values=poc-max-weather-infra" \
                "Name=instance-state-name,Values=running" \
     --query 'Reservations[].Instances[].InstanceId' --output text
   ```

2. Get the private EKS API endpoint:

   ```bash
   aws eks describe-cluster --name poc-max-weather-cluster \
     --query 'cluster.endpoint' --output text
   # Returns: https://<hash>.gr7.us-east-1.eks.amazonaws.com
   # Strip the "https://" prefix; that is your <eks-private-endpoint-host>
   ```

3. Open SSM tunnel:

   ```bash
   aws ssm start-session \
     --target <infra-instance-id> \
     --document-name AWS-StartPortForwardingSessionToRemoteHost \
     --parameters host="<eks-private-endpoint-host>",portNumber="443",localPortNumber="6443"
   ```

4. Patch kubeconfig to route through the tunnel (new terminal):

   ```bash
   kubectl config set-cluster <cluster-arn> --server=https://localhost:6443
   kubectl config set-cluster <cluster-arn> --insecure-skip-tls-verify=true
   kubectl get nodes
   ```

### Path C — update allowlist and re-apply (use sparingly)

If your IP changed and SSM is not available:

1. Update `endpoint_public_access_cidrs` in `infra/envs/poc/terraform.tfvars`.
2. Apply only the EKS module:

   ```bash
   terraform -chdir=infra/envs/poc apply -target=module.eks -auto-approve
   ```

3. Run `make kubeconfig` to refresh local credentials.

---

## Troubleshooting

**ENI quota exceeded on VPCE creation**
Symptom: `LimitExceeded: Network interfaces limit exceeded`. Each interface VPCE consumes one ENI
per AZ. Request a quota increase for "Network interfaces per Region" in Service Quotas, or remove
unneeded VPCEs from `infra/envs/poc/main.tf`.

**AZ unavailable on NAT Gateway creation**
Symptom: `InsufficientFreeAddressesInSubnet` or capacity error on specific AZ. Update
`availability_zones` in `terraform.tfvars` to substitute a different AZ.

**kubectl unreachable after apply**
Check that your current outbound IP matches the allowlist:

```bash
aws eks describe-cluster --name poc-max-weather-cluster \
  --query 'cluster.resourcesVpcConfig.publicAccessCidrs'
curl -s ifconfig.me
```

If they don't match, use Path B (SSM) or Path C (re-apply) from the Operator kubectl access
section.

**Karpenter not provisioning nodes**
Check the NodeClass subnet selector matches private subnet tags, then inspect logs:

```bash
kubectl logs -n karpenter deployment/karpenter --tail=100
```

Common causes: missing `karpenter.sh/discovery: poc-max-weather-cluster` tag on private subnets,
or IAM Pod Identity association not yet propagated.

**Internal NLB shows Scheme=internet-facing**
Root cause: ingress-nginx uses the in-tree AWS cloud-provider (no AWS Load Balancer Controller).
The in-tree provisioner honors ONLY the legacy annotation
`service.beta.kubernetes.io/aws-load-balancer-internal: "true"`. The modern
`aws-load-balancer-scheme: internal` annotation is silently ignored.

Fix:

1. Confirm `service.beta.kubernetes.io/aws-load-balancer-internal: "true"` is in
   `infra/envs/poc/eks-self-managed-addons/values/ingress-nginx.yaml` under
   `controller.service.annotations`.
2. Re-apply: `terraform -chdir=infra/envs/poc apply -target=module.eks_self_managed_addons.helm_release.ingress_nginx`
3. Force NLB recreate: `kubectl delete svc -n ingress-nginx ingress-nginx-controller`
4. Wait ~2 min for Helm to recreate the Service and AWS to provision a new NLB.

**CoreDNS pods pending**
CoreDNS must be installed after nodes are ready. If the addon was applied pre-node (wrong phase),
the pods stay `Pending` with no schedulable node. Fix: ensure `depends_on_node_group = true` is
set for the `coredns` entry in `cluster_addons` in `infra/envs/poc/variables.tf`, then re-apply
stage2.

**Helm provider "Kubernetes cluster unreachable" on plan**
The Helm provider 2.x has a refresh race condition. Use:

```bash
terraform -chdir=infra/envs/poc plan -refresh=false
```

Apply still works normally; this only affects plan UX.

**Non-ASCII characters rejected by EC2 API**
Symptom: `InvalidParameterValue: Character sets beyond ASCII are not supported` during apply.
AWS rejects em-dashes and other non-ASCII in `aws_security_group.description`. Terraform
`validate` does NOT catch this. Keep all SG descriptions strictly ASCII (hyphens, not dashes).

**`path.cwd` resolves to wrong directory**
Running `terraform plan -chdir=infra/envs/poc` from the repo root causes `basename(path.cwd)` to
evaluate to the outer directory name instead of `poc`, producing wrong resource names
(`assessment-max-weather-*` instead of `poc-max-weather-*`). Always use the Makefile targets,
which `cd infra/envs/poc` before invoking Terraform.

**Staged apply fails mid-way**
Re-run only the failing stage. Each stage is idempotent. Do not re-run `make apply-all` from the
beginning if stages 1 and 2 already succeeded; run `make apply-stage3` only.

---

## Teardown

### Interactive (default)

```bash
make teardown
```

Prompts for the literal phrase `destroy max-weather` before proceeding. Refuses to continue if
any other string is entered.

### Non-interactive (CI)

```bash
make teardown-force
```

Pipes the confirmation phrase automatically. Intended for CI pipelines only.

### What teardown does

1. Destroys workload state (`infra/envs/poc/`) via Terraform destroy.
2. Destroys bootstrap state (`infra/bootstrap/`) — S3 bucket (`force_destroy=true`) and DynamoDB
   table.
3. Runs `cloud-nuke` with `.cloud-nuke.yaml` to sweep any orphaned resources matching
   `*max-weather*`, including the tfstate S3 bucket and tflock DynamoDB table.

After teardown, the AWS account contains zero Max Weather resources. Re-deploying requires
starting from step 2 (bootstrap) of the Bring-up section.

> **Warning**: Teardown is irreversible. All data, secrets, and logs are destroyed.
> There is no recovery window for Secrets Manager secrets (forced delete).
