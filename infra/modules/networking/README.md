# Networking Module

Creates a multi-AZ VPC for an EKS cluster with **public subnets only**, an
Internet Gateway, and a single shared public route table. This is a deliberate
**POC topology**: there are no private subnets, no NAT Gateway, and no VPC
endpoints. Worker nodes are placed in the public subnets and receive public IPs.

> **POC trade-off** — for production, use private subnets + NAT Gateway (or VPC
> endpoints for ECR / Logs / S3 / STS). The POC topology was chosen to stay
> close to AWS Free Tier (a NAT Gateway alone is ~$32/month + data processing
> charges and never sleeps).

## Resource naming

Every resource Name tag derives from `var.name` plus a per-resource suffix.
With `var.name = "poc-max-weather"` and the default suffixes:

| Resource                    | Name tag                                  |
|-----------------------------|-------------------------------------------|
| VPC                         | `poc-max-weather-vpc`                     |
| Internet Gateway            | `poc-max-weather-igw`                     |
| Public subnet (per AZ)      | `poc-max-weather-public-us-east-1a` ...   |
| Public route table          | `poc-max-weather-public-rt`               |

The cluster-discovery tag VALUES are independent of the Name tag — see below.

## Subnet tagging (cluster discovery)

Every public subnet is tagged so that EKS, the AWS Load Balancer Controller,
and Karpenter can discover it automatically. The cluster name in the tag VALUES
is `var.eks_cluster_name` (falling back to `var.name` when empty), so this
module's resource Name tags can use a short prefix while the EKS-specific tags
carry the full cluster name (e.g. `poc-max-weather-cluster`).

| Tag                                          | Value                                | Purpose                                |
|----------------------------------------------|--------------------------------------|----------------------------------------|
| `kubernetes.io/cluster/<eks_cluster_name>`   | `shared`                             | EKS subnet discovery                   |
| `kubernetes.io/role/elb`                     | `1`                                  | Internet-facing LBs (default for POC)  |
| `kubernetes.io/role/internal-elb`            | `1`                                  | Internal LBs (kept so prod can flip)   |
| `karpenter.sh/discovery`                     | `<eks_cluster_name>`                 | Karpenter `EC2NodeClass.subnetSelectorTerms` |

## Usage

```hcl
module "networking" {
  source = "../../modules/networking"

  name             = local.master_prefix              # e.g. "poc-max-weather"
  eks_cluster_name = "${local.master_prefix}-cluster" # full EKS cluster name

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
| `name` | Resource name prefix (typically `local.master_prefix`). Used for VPC / IGW / subnet / route-table Name tags. | `string` | n/a | yes |
| `eks_cluster_name` | Full EKS cluster name used as the value of `kubernetes.io/cluster/<name>` and `karpenter.sh/discovery` subnet tags. Empty falls back to `var.name`. | `string` | `""` | no |
| `vpc_cidr` | IPv4 CIDR block for the VPC. | `string` | `"10.20.0.0/16"` | no |
| `availability_zones` | List of AZs for subnet distribution. Length must match `public_subnet_cidrs`. | `list(string)` | n/a | yes |
| `public_subnet_cidrs` | CIDR blocks for public subnets (one per AZ). | `list(string)` | `["10.20.1.0/24", "10.20.2.0/24", "10.20.3.0/24"]` | no |
| `enable_dns_hostnames` | Enable DNS hostnames in the VPC. | `bool` | `true` | no |
| `enable_dns_support` | Enable DNS support in the VPC. | `bool` | `true` | no |
| `tags` | Common tags applied to all resources. | `map(string)` | `{}` | no |
| `vpc_name_suffix` | Suffix appended to `var.name` for the VPC `Name` tag. | `string` | `"-vpc"` | no |
| `internet_gateway_name_suffix` | Suffix appended to `var.name` for the IGW `Name` tag. | `string` | `"-igw"` | no |
| `public_subnet_name_prefix` | Prefix appended to `var.name` (followed by AZ name) for each public subnet's `Name` tag. | `string` | `"-public-"` | no |
| `public_subnet_name_suffix` | Suffix appended after the AZ component of each public subnet's `Name` tag. | `string` | `""` | no |
| `public_route_table_name_suffix` | Suffix appended to `var.name` for the public route table `Name` tag. | `string` | `"-public-rt"` | no |
| `map_public_ip_on_launch` | Whether public subnets assign a public IPv4 to instances launched into them. | `bool` | `true` | no |
| `public_route_destination_cidr_block` | Destination CIDR for the default route in the public route table. | `string` | `"0.0.0.0/0"` | no |
| `subnet_tag_role_elb_key` | Tag key for AWS LB Controller internet-facing LB subnet discovery. | `string` | `"kubernetes.io/role/elb"` | no |
| `subnet_tag_role_internal_elb_key` | Tag key for AWS LB Controller internal LB subnet discovery. | `string` | `"kubernetes.io/role/internal-elb"` | no |
| `subnet_tag_role_elb_value` | Value for both `kubernetes.io/role/elb` and `kubernetes.io/role/internal-elb`. | `string` | `"1"` | no |
| `subnet_tag_cluster_key_prefix` | Prefix for the EKS subnet discovery tag (cluster name appended). | `string` | `"kubernetes.io/cluster/"` | no |
| `subnet_tag_cluster_value` | Value for the `kubernetes.io/cluster/<cluster_name>` tag. | `string` | `"shared"` | no |
| `subnet_tag_karpenter_discovery_key` | Tag key consumed by Karpenter `EC2NodeClass.subnetSelectorTerms`. | `string` | `"karpenter.sh/discovery"` | no |

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
| aws | `~> 6.0` |

## Promoting to a Production Topology

To move from POC to a production-grade network:

1. Re-introduce `aws_subnet "private"` (one per AZ) without `map_public_ip_on_launch`.
2. Re-introduce `aws_eip` + `aws_nat_gateway` (one per AZ for HA, or a single NAT for cost).
3. Add per-AZ `aws_route_table "private"` with a default route to the corresponding NAT.
4. Move the `kubernetes.io/role/internal-elb` tag from public to private subnets.
5. Update the env composition to pass `module.networking.private_subnet_ids` to the EKS module.
6. Optionally add Interface VPC Endpoints (ECR API, ECR DKR, CloudWatch Logs, STS) and a Gateway endpoint for S3 to avoid NAT egress charges for AWS-internal traffic.
