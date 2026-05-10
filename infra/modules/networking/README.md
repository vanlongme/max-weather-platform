# Networking Module

Creates a 3-AZ VPC for an EKS cluster with public and private subnets, an Internet Gateway, NAT Gateway(s), routing, and VPC endpoints (ECR API, ECR DKR, CloudWatch Logs as Interface; S3 as Gateway).

Subnets are tagged for EKS load-balancer auto-discovery
(`kubernetes.io/role/elb` on public, `kubernetes.io/role/internal-elb` on private,
`kubernetes.io/cluster/<cluster_name> = shared` on both).

## Usage

```hcl
module "networking" {
  source = "../../modules/networking"

  cluster_name       = "max-weather"
  vpc_cidr           = "10.20.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]

  public_subnet_cidrs  = ["10.20.1.0/24", "10.20.2.0/24", "10.20.3.0/24"]
  private_subnet_cidrs = ["10.20.11.0/24", "10.20.12.0/24", "10.20.13.0/24"]

  single_nat_gateway = true

  tags = {
    Project     = "max-weather"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `cluster_name` | EKS cluster name, used for subnet tagging and resource naming. | `string` | n/a | yes |
| `vpc_cidr` | IPv4 CIDR block for the VPC. | `string` | `"10.20.0.0/16"` | no |
| `availability_zones` | List of AZs for subnet distribution. Length must match the public/private CIDR lists. | `list(string)` | n/a | yes |
| `public_subnet_cidrs` | CIDR blocks for public subnets (one per AZ). | `list(string)` | `["10.20.1.0/24", "10.20.2.0/24", "10.20.3.0/24"]` | no |
| `private_subnet_cidrs` | CIDR blocks for private subnets (one per AZ). | `list(string)` | `["10.20.11.0/24", "10.20.12.0/24", "10.20.13.0/24"]` | no |
| `single_nat_gateway` | Use a single NAT Gateway instead of one per AZ (cost optimization). | `bool` | `true` | no |
| `enable_dns_hostnames` | Enable DNS hostnames in the VPC. | `bool` | `true` | no |
| `enable_dns_support` | Enable DNS support in the VPC. | `bool` | `true` | no |
| `tags` | Common tags applied to all resources. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `vpc_id` | ID of the VPC. |
| `vpc_cidr_block` | CIDR block of the VPC. |
| `public_subnet_ids` | List of IDs of the public subnets. |
| `private_subnet_ids` | List of IDs of the private subnets. |
| `nat_gateway_id` | ID of the first (or only) NAT Gateway. |
| `nat_gateway_public_ip` | Public IP of the first (or only) NAT Gateway EIP. |
| `public_route_table_id` | ID of the public route table. |
| `private_route_table_ids` | List of private route table IDs (one per AZ). |
| `internet_gateway_id` | ID of the Internet Gateway. |

## Requirements

| Name | Version |
|------|---------|
| terraform | `>= 1.9, < 2.0` |
| aws | `~> 5.60` |
