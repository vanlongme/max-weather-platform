# Networking Module

Multi-AZ VPC for an EKS cluster. Supports three composable topologies driven by which subnet-CIDR lists you populate:

| Topology | `public_subnet_cidrs` | `private_subnet_cidrs` | `enable_vpc_endpoints` | `enable_nat_gateway` | `secondary_vpc_cidrs` + `pod_subnet_cidrs` |
|----------|-----------------------|------------------------|------------------------|----------------------|--------------------------------------------|
| Public-only POC | set | `[]` | `false` | `false` | `[]` |
| Fully-private (recommended) | `[]` or set | set | `true` | `false` | `[]` |
| Fully-private + VPC CNI custom networking | `[]` or set | set | `true` | `false` | set |

Resources are created **only** when the corresponding CIDR list is non-empty (IGW only when public subnets exist; private route table only when private subnets exist; etc.).

## Resource naming

Every resource Name tag derives from `var.name` + per-resource suffix. With `var.name = "poc-max-weather"`:

| Resource                              | Name tag                                |
|---------------------------------------|-----------------------------------------|
| VPC                                   | `poc-max-weather-vpc`                   |
| Internet Gateway (when public)        | `poc-max-weather-igw`                   |
| NAT Gateway (when enabled)            | `poc-max-weather-nat`                   |
| Public subnet (per AZ)                | `poc-max-weather-public-us-east-1a` …   |
| Private subnet (per AZ)               | `poc-max-weather-private-us-east-1a` …  |
| Pod subnet (per AZ, secondary CIDR)   | `poc-max-weather-pod-us-east-1a` …      |
| Public/Private route table            | `poc-max-weather-public-rt` / `-private-rt` |
| VPC endpoint security group           | `poc-max-weather-vpce-sg`               |

## Subnet tagging (cluster discovery)

Cluster-discovery tag VALUES use `var.eks_cluster_name` (fallback `var.name`).

| Subnet kind | `kubernetes.io/cluster/<cluster>` | `kubernetes.io/role/elb` | `kubernetes.io/role/internal-elb` | `karpenter.sh/discovery` |
|-------------|-----------------------------------|--------------------------|------------------------------------|--------------------------|
| Public      | `shared` | `1` | — | `<cluster>` |
| Private     | `shared` | — | `1` | `<cluster>` |
| Pod (2nd CIDR) | `owned` | — | `1` | `<cluster>` |

Pod subnets use `owned` (vs `shared`) per the VPC CNI custom-networking guidance, and DO NOT carry `kubernetes.io/role/elb` (LBs must never land on the secondary range).

## Usage — Fully-private cluster

```hcl
module "networking" {
  source = "../../modules/networking"

  name             = local.master_prefix
  eks_cluster_name = "${local.master_prefix}-cluster"

  vpc_cidr             = "10.20.0.0/16"
  availability_zones   = ["us-east-1a", "us-east-1b", "us-east-1c"]
  public_subnet_cidrs  = []                                              # no public subnets
  private_subnet_cidrs = ["10.20.11.0/24", "10.20.12.0/24", "10.20.13.0/24"]

  enable_nat_gateway   = false   # private SDK traffic flows over VPC endpoints
  enable_vpc_endpoints = true    # creates the canonical EKS-private endpoint set + S3 gateway

  tags = { Environment = "poc", Project = "max-weather", ManagedBy = "terraform" }
}
```

The default `vpc_interface_endpoints` map ships 18 endpoints: the canonical EKS private-cluster set (ec2, ecr.api, ecr.dkr, sts, logs, eks, eks-auth, kms, sqs, autoscaling, elasticloadbalancing, ssm, ssmmessages, ec2messages) plus four observability and secret-management endpoints (monitoring, secretsmanager, elasticfilesystem, xray). Supplying a custom map **REPLACES** it — re-declare every entry you want kept.

## Usage — VPC CNI custom networking ("2nd networking")

Add a secondary CIDR + one pod subnet per AZ to the fully-private composition. The EKS module then consumes `module.networking.pod_subnet_ids_by_az` to render ENIConfig CRs.

```hcl
module "networking" {
  source = "../../modules/networking"

  name             = local.master_prefix
  eks_cluster_name = "${local.master_prefix}-cluster"

  vpc_cidr             = "10.20.0.0/16"
  availability_zones   = ["us-east-1a", "us-east-1b", "us-east-1c"]
  public_subnet_cidrs  = []
  private_subnet_cidrs = ["10.20.11.0/24", "10.20.12.0/24", "10.20.13.0/24"]

  # 2nd networking — pod CIDRs come from secondary range, NOT primary VPC CIDR.
  secondary_vpc_cidrs = ["100.64.0.0/16"]
  pod_subnet_cidrs    = ["100.64.0.0/19", "100.64.32.0/19", "100.64.64.0/19"]

  enable_nat_gateway   = false
  enable_vpc_endpoints = true

  tags = { Environment = "poc", Project = "max-weather", ManagedBy = "terraform" }
}

module "eks" {
  source = "../../modules/eks"
  # … other inputs …
  enable_vpc_cni_custom_networking = true
  pod_subnet_ids_by_az             = module.networking.pod_subnet_ids_by_az
}
```

Pod subnets share the private route table (`aws_route_table_association.pod`), so pod egress traverses the same VPC endpoints / NAT as node egress. Pod subnet CIDRs MUST lie inside `secondary_vpc_cidrs`; AZ count of `pod_subnet_cidrs` MUST match `availability_zones`.

Complete invocation: [`terraform.tfvars.example`](./terraform.tfvars.example).

## Deviations from upstream canonical

**Branch**: `feat/private-cluster-hardening` | **Date**: 2026-05-26

No deviations in this branch. All features used in this environment (private subnets, NAT Gateway, VPC interface endpoints, S3 gateway endpoint, VPCE security group, `kubernetes.io/role/internal-elb` subnet tagging) are upstream-canonical and were merely under-utilized in prior caller configurations. The module source is byte-identical to the canonical upstream version.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9, < 2.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.44.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_eip.nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_internet_gateway.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway) | resource |
| [aws_nat_gateway.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/nat_gateway) | resource |
| [aws_route_table.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table_association.pod](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_security_group.vpc_endpoints](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_subnet.pod](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [aws_vpc_endpoint.interface](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_endpoint.s3_gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_ipv4_cidr_block_association.secondary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_ipv4_cidr_block_association) | resource |
| [aws_vpc_security_group_ingress_rule.vpc_endpoints_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_availability_zones"></a> [availability\_zones](#input\_availability\_zones) | List of availability zones for subnet distribution. Length must match each provided subnet CIDR list. | `list(string)` | n/a | yes |
| <a name="input_eks_cluster_name"></a> [eks\_cluster\_name](#input\_eks\_cluster\_name) | Full EKS cluster name used as the VALUE of the kubernetes.io/cluster/<cluster\_name> subnet tag and as the value of the karpenter.sh/discovery subnet tag. Empty string falls back to var.name. | `string` | `""` | no |
| <a name="input_enable_dns_hostnames"></a> [enable\_dns\_hostnames](#input\_enable\_dns\_hostnames) | Enable DNS hostnames in the VPC. | `bool` | `true` | no |
| <a name="input_enable_dns_support"></a> [enable\_dns\_support](#input\_enable\_dns\_support) | Enable DNS support in the VPC. | `bool` | `true` | no |
| <a name="input_enable_nat_gateway"></a> [enable\_nat\_gateway](#input\_enable\_nat\_gateway) | Whether to create a single NAT Gateway (in the first public subnet) and route private subnets through it. When false (recommended for fully-private with VPC endpoints), private subnets have no default route to the internet. | `bool` | `false` | no |
| <a name="input_enable_s3_gateway_endpoint"></a> [enable\_s3\_gateway\_endpoint](#input\_enable\_s3\_gateway\_endpoint) | Whether to create the S3 gateway endpoint. Required for ECR image layer pulls in a fully-private cluster. | `bool` | `true` | no |
| <a name="input_enable_vpc_endpoints"></a> [enable\_vpc\_endpoints](#input\_enable\_vpc\_endpoints) | Whether to create the VPC endpoints required for a fully-private EKS cluster (interface + S3 gateway). | `bool` | `false` | no |
| <a name="input_internet_gateway_name_suffix"></a> [internet\_gateway\_name\_suffix](#input\_internet\_gateway\_name\_suffix) | n/a | `string` | `"-igw"` | no |
| <a name="input_map_public_ip_on_launch"></a> [map\_public\_ip\_on\_launch](#input\_map\_public\_ip\_on\_launch) | Whether public subnets assign a public IPv4 to instances launched into them. | `bool` | `true` | no |
| <a name="input_name"></a> [name](#input\_name) | Name prefix applied to every networking resource (typically the master\_prefix from the composition, e.g. 'poc-max-weather'). | `string` | n/a | yes |
| <a name="input_nat_eip_name_suffix"></a> [nat\_eip\_name\_suffix](#input\_nat\_eip\_name\_suffix) | n/a | `string` | `"-nat-eip"` | no |
| <a name="input_nat_gateway_name_suffix"></a> [nat\_gateway\_name\_suffix](#input\_nat\_gateway\_name\_suffix) | n/a | `string` | `"-nat"` | no |
| <a name="input_pod_subnet_cidrs"></a> [pod\_subnet\_cidrs](#input\_pod\_subnet\_cidrs) | CIDR blocks for pod subnets (one per AZ) carved from secondary\_vpc\_cidrs. VPC CNI custom networking assigns pod IPs from these subnets via ENIConfig CRs (caller-applied). Must lie inside secondary\_vpc\_cidrs. Empty = feature disabled. | `list(string)` | `[]` | no |
| <a name="input_pod_subnet_name_prefix"></a> [pod\_subnet\_name\_prefix](#input\_pod\_subnet\_name\_prefix) | n/a | `string` | `"-pod-"` | no |
| <a name="input_private_route_table_name_suffix"></a> [private\_route\_table\_name\_suffix](#input\_private\_route\_table\_name\_suffix) | n/a | `string` | `"-private-rt"` | no |
| <a name="input_private_subnet_cidrs"></a> [private\_subnet\_cidrs](#input\_private\_subnet\_cidrs) | CIDR blocks for private subnets (one per AZ). Workers in a fully-private cluster live here. Set to [] to skip. | `list(string)` | `[]` | no |
| <a name="input_private_subnet_name_prefix"></a> [private\_subnet\_name\_prefix](#input\_private\_subnet\_name\_prefix) | n/a | `string` | `"-private-"` | no |
| <a name="input_public_route_destination_cidr_block"></a> [public\_route\_destination\_cidr\_block](#input\_public\_route\_destination\_cidr\_block) | Destination CIDR for the default route in the public route table. | `string` | `"0.0.0.0/0"` | no |
| <a name="input_public_route_table_name_suffix"></a> [public\_route\_table\_name\_suffix](#input\_public\_route\_table\_name\_suffix) | n/a | `string` | `"-public-rt"` | no |
| <a name="input_public_subnet_cidrs"></a> [public\_subnet\_cidrs](#input\_public\_subnet\_cidrs) | CIDR blocks for public subnets (one per AZ). Set to [] to skip public subnets entirely (fully-private cluster topology). | `list(string)` | <pre>[<br/>  "10.20.1.0/24",<br/>  "10.20.2.0/24",<br/>  "10.20.3.0/24"<br/>]</pre> | no |
| <a name="input_public_subnet_name_prefix"></a> [public\_subnet\_name\_prefix](#input\_public\_subnet\_name\_prefix) | n/a | `string` | `"-public-"` | no |
| <a name="input_public_subnet_name_suffix"></a> [public\_subnet\_name\_suffix](#input\_public\_subnet\_name\_suffix) | n/a | `string` | `""` | no |
| <a name="input_secondary_vpc_cidrs"></a> [secondary\_vpc\_cidrs](#input\_secondary\_vpc\_cidrs) | Additional CIDR blocks to associate with the VPC. Required for VPC CNI custom networking ('2nd networking') so pods can use IPs from a separate, large range (commonly 100.64.0.0/16) while nodes stay on the primary CIDR. Empty = feature disabled. | `list(string)` | `[]` | no |
| <a name="input_subnet_tag_cluster_key_prefix"></a> [subnet\_tag\_cluster\_key\_prefix](#input\_subnet\_tag\_cluster\_key\_prefix) | Prefix for the EKS cluster subnet discovery tag. Full key = <prefix><cluster\_name>. | `string` | `"kubernetes.io/cluster/"` | no |
| <a name="input_subnet_tag_cluster_value"></a> [subnet\_tag\_cluster\_value](#input\_subnet\_tag\_cluster\_value) | Tag value for the kubernetes.io/cluster/<cluster\_name> subnet discovery tag. | `string` | `"shared"` | no |
| <a name="input_subnet_tag_karpenter_discovery_key"></a> [subnet\_tag\_karpenter\_discovery\_key](#input\_subnet\_tag\_karpenter\_discovery\_key) | Subnet tag key consumed by Karpenter EC2NodeClass.subnetSelectorTerms. | `string` | `"karpenter.sh/discovery"` | no |
| <a name="input_subnet_tag_role_elb_key"></a> [subnet\_tag\_role\_elb\_key](#input\_subnet\_tag\_role\_elb\_key) | Subnet tag key consumed by the AWS Load Balancer Controller for internet-facing LBs. | `string` | `"kubernetes.io/role/elb"` | no |
| <a name="input_subnet_tag_role_elb_value"></a> [subnet\_tag\_role\_elb\_value](#input\_subnet\_tag\_role\_elb\_value) | Tag value applied to subnets for the kubernetes.io/role/elb and internal-elb keys. | `string` | `"1"` | no |
| <a name="input_subnet_tag_role_internal_elb_key"></a> [subnet\_tag\_role\_internal\_elb\_key](#input\_subnet\_tag\_role\_internal\_elb\_key) | Subnet tag key consumed by the AWS Load Balancer Controller for internal LBs. | `string` | `"kubernetes.io/role/internal-elb"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Common tags applied to all resources. | `map(string)` | `{}` | no |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | IPv4 CIDR block for the VPC. | `string` | `"10.20.0.0/16"` | no |
| <a name="input_vpc_endpoint_private_dns_enabled"></a> [vpc\_endpoint\_private\_dns\_enabled](#input\_vpc\_endpoint\_private\_dns\_enabled) | Whether private DNS is enabled on interface endpoints. Required so SDK calls to *.amazonaws.com hostnames resolve to endpoint ENIs. | `bool` | `true` | no |
| <a name="input_vpc_endpoint_sg_name_suffix"></a> [vpc\_endpoint\_sg\_name\_suffix](#input\_vpc\_endpoint\_sg\_name\_suffix) | n/a | `string` | `"-vpce-sg"` | no |
| <a name="input_vpc_interface_endpoints"></a> [vpc\_interface\_endpoints](#input\_vpc\_interface\_endpoints) | Map of interface VPC endpoints to create. Key = service short name; value = service suffix appended to com.amazonaws.<region>. Default ships 18 endpoints: the canonical EKS-private-cluster set (ec2, ecr.api, ecr.dkr, sts, logs, eks, eks-auth, kms, sqs, autoscaling, elasticloadbalancing, ssm, ssmmessages, ec2messages) plus monitoring, secretsmanager, elasticfilesystem, xray. | `map(string)` | <pre>{<br/>  "autoscaling": "autoscaling",<br/>  "ec2": "ec2",<br/>  "ec2messages": "ec2messages",<br/>  "ecr_api": "ecr.api",<br/>  "ecr_dkr": "ecr.dkr",<br/>  "eks": "eks",<br/>  "eks_auth": "eks-auth",<br/>  "elasticfilesystem": "elasticfilesystem",<br/>  "elasticloadbalancing": "elasticloadbalancing",<br/>  "kms": "kms",<br/>  "logs": "logs",<br/>  "monitoring": "monitoring",<br/>  "secretsmanager": "secretsmanager",<br/>  "sqs": "sqs",<br/>  "ssm": "ssm",<br/>  "ssmmessages": "ssmmessages",<br/>  "sts": "sts",<br/>  "xray": "xray"<br/>}</pre> | no |
| <a name="input_vpc_name_suffix"></a> [vpc\_name\_suffix](#input\_vpc\_name\_suffix) | n/a | `string` | `"-vpc"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_internet_gateway_id"></a> [internet\_gateway\_id](#output\_internet\_gateway\_id) | ID of the Internet Gateway. Null when no public subnets. |
| <a name="output_nat_gateway_id"></a> [nat\_gateway\_id](#output\_nat\_gateway\_id) | ID of the NAT Gateway. Null when enable\_nat\_gateway = false. |
| <a name="output_pod_subnet_ids"></a> [pod\_subnet\_ids](#output\_pod\_subnet\_ids) | List of IDs of the pod subnets carved from secondary\_vpc\_cidrs (one per AZ). Empty when VPC CNI custom networking is disabled. |
| <a name="output_pod_subnet_ids_by_az"></a> [pod\_subnet\_ids\_by\_az](#output\_pod\_subnet\_ids\_by\_az) | Map of AZ name to pod subnet ID. Caller feeds this directly into per-AZ ENIConfig CRs for the VPC CNI. |
| <a name="output_private_route_table_id"></a> [private\_route\_table\_id](#output\_private\_route\_table\_id) | ID of the private route table. Null when no private subnets. |
| <a name="output_private_subnet_ids"></a> [private\_subnet\_ids](#output\_private\_subnet\_ids) | List of IDs of the private subnets (one per AZ). Empty when private\_subnet\_cidrs = []. |
| <a name="output_public_route_table_id"></a> [public\_route\_table\_id](#output\_public\_route\_table\_id) | ID of the public route table. Null when no public subnets. |
| <a name="output_public_subnet_ids"></a> [public\_subnet\_ids](#output\_public\_subnet\_ids) | List of IDs of the public subnets (one per AZ). Empty when public\_subnet\_cidrs = []. |
| <a name="output_s3_gateway_endpoint_id"></a> [s3\_gateway\_endpoint\_id](#output\_s3\_gateway\_endpoint\_id) | ID of the S3 gateway endpoint. Null when not created. |
| <a name="output_secondary_vpc_cidr_block_associations"></a> [secondary\_vpc\_cidr\_block\_associations](#output\_secondary\_vpc\_cidr\_block\_associations) | Secondary VPC CIDR association IDs (one per secondary\_vpc\_cidrs entry). |
| <a name="output_vpc_cidr_block"></a> [vpc\_cidr\_block](#output\_vpc\_cidr\_block) | CIDR block of the VPC. |
| <a name="output_vpc_endpoint_ids"></a> [vpc\_endpoint\_ids](#output\_vpc\_endpoint\_ids) | Map of interface VPC endpoint IDs keyed by short name. Empty when enable\_vpc\_endpoints = false. |
| <a name="output_vpc_endpoint_security_group_id"></a> [vpc\_endpoint\_security\_group\_id](#output\_vpc\_endpoint\_security\_group\_id) | Security group attached to all interface VPC endpoints. Null when enable\_vpc\_endpoints = false. |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | ID of the VPC. |
<!-- END_TF_DOCS -->
