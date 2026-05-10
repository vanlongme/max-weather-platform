# Networking Module

Creates a multi-AZ VPC for an EKS cluster with **public subnets only**, an
Internet Gateway, and a single shared public route table. This is a deliberate
**POC topology**: there are no private subnets, no NAT Gateway, and no VPC
endpoints. Worker nodes are placed in the public subnets and receive public IPs.

> **POC trade-off** — for production, use private subnets + NAT Gateway (or VPC
> endpoints for ECR / Logs / S3 / STS). The POC topology was chosen to stay
> close to AWS Free Tier (a NAT Gateway alone is ~$32/month + data processing
> charges and never sleeps).

## Subnet Tagging

Every public subnet is tagged so that EKS, the AWS Load Balancer Controller,
and Karpenter can discover it automatically:

| Tag | Value | Purpose |
|-----|-------|---------|
| `kubernetes.io/cluster/<cluster_name>` | `shared` | EKS subnet discovery |
| `kubernetes.io/role/elb` | `1` | Internet-facing LBs (default for POC) |
| `kubernetes.io/role/internal-elb` | `1` | Internal LBs (kept so prod overlay can flip) |
| `karpenter.sh/discovery` | `<cluster_name>` | Karpenter `EC2NodeClass.subnetSelectorTerms` |

## Usage

```hcl
module "networking" {
  source = "../../modules/networking"

  cluster_name       = "max-weather"
  vpc_cidr           = "10.20.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]

  public_subnet_cidrs = ["10.20.1.0/24", "10.20.2.0/24", "10.20.3.0/24"]

  tags = {
    Project     = "max-weather"
    Environment = "poc"
    ManagedBy   = "terraform"
  }
}
```

A complete invocation lives in [`terraform.tfvars.example`](./terraform.tfvars.example).

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `cluster_name` | EKS cluster name, used for subnet tagging and resource naming. | `string` | n/a | yes |
| `vpc_cidr` | IPv4 CIDR block for the VPC. | `string` | `"10.20.0.0/16"` | no |
| `availability_zones` | List of AZs for subnet distribution. Length must match `public_subnet_cidrs`. | `list(string)` | n/a | yes |
| `public_subnet_cidrs` | CIDR blocks for public subnets (one per AZ). | `list(string)` | `["10.20.1.0/24", "10.20.2.0/24", "10.20.3.0/24"]` | no |
| `enable_dns_hostnames` | Enable DNS hostnames in the VPC. | `bool` | `true` | no |
| `enable_dns_support` | Enable DNS support in the VPC. | `bool` | `true` | no |
| `tags` | Common tags applied to all resources. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `vpc_id` | ID of the VPC. |
| `vpc_cidr_block` | CIDR block of the VPC. |
| `public_subnet_ids` | List of IDs of the public subnets (used for both worker placement and load balancers). |
| `public_route_table_id` | ID of the public route table. |
| `internet_gateway_id` | ID of the Internet Gateway. |

## Requirements

| Name | Version |
|------|---------|
| terraform | `>= 1.9, < 2.0` |
| aws | `~> 5.60` |

## Promoting to a Production Topology

To move from POC to a production-grade network:

1. Re-introduce `aws_subnet "private"` (one per AZ) without `map_public_ip_on_launch`.
2. Re-introduce `aws_eip` + `aws_nat_gateway` (one per AZ for HA, or a single NAT for cost).
3. Add per-AZ `aws_route_table "private"` with a default route to the corresponding NAT.
4. Move the `kubernetes.io/role/internal-elb` tag from public to private subnets.
5. Update the env composition to pass `module.networking.private_subnet_ids` to the EKS module.
6. Optionally add Interface VPC Endpoints (ECR API, ECR DKR, CloudWatch Logs, STS) and a Gateway endpoint for S3 to avoid NAT egress charges for AWS-internal traffic.
