output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "List of IDs of the public subnets (one per AZ). Empty when public_subnet_cidrs = []."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of IDs of the private subnets (one per AZ). Empty when private_subnet_cidrs = []."
  value       = aws_subnet.private[*].id
}

output "public_route_table_id" {
  description = "ID of the public route table. Null when no public subnets."
  value       = length(aws_route_table.public) > 0 ? aws_route_table.public[0].id : null
}

output "private_route_table_id" {
  description = "ID of the private route table. Null when no private subnets."
  value       = length(aws_route_table.private) > 0 ? aws_route_table.private[0].id : null
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway. Null when no public subnets."
  value       = length(aws_internet_gateway.main) > 0 ? aws_internet_gateway.main[0].id : null
}

output "nat_gateway_id" {
  description = "ID of the NAT Gateway. Null when enable_nat_gateway = false."
  value       = length(aws_nat_gateway.main) > 0 ? aws_nat_gateway.main[0].id : null
}

output "vpc_endpoint_security_group_id" {
  description = "Security group attached to all interface VPC endpoints. Null when enable_vpc_endpoints = false."
  value       = length(aws_security_group.vpc_endpoints) > 0 ? aws_security_group.vpc_endpoints[0].id : null
}

output "vpc_endpoint_ids" {
  description = "Map of interface VPC endpoint IDs keyed by short name. Empty when enable_vpc_endpoints = false."
  value       = { for k, v in aws_vpc_endpoint.interface : k => v.id }
}

output "s3_gateway_endpoint_id" {
  description = "ID of the S3 gateway endpoint. Null when not created."
  value       = length(aws_vpc_endpoint.s3_gateway) > 0 ? aws_vpc_endpoint.s3_gateway[0].id : null
}

output "pod_subnet_ids" {
  description = "List of IDs of the pod subnets carved from secondary_vpc_cidrs (one per AZ). Empty when VPC CNI custom networking is disabled."
  value       = aws_subnet.pod[*].id
}

output "pod_subnet_ids_by_az" {
  description = "Map of AZ name to pod subnet ID. Caller feeds this directly into per-AZ ENIConfig CRs for the VPC CNI."
  value       = { for s in aws_subnet.pod : s.availability_zone => s.id }
}

output "secondary_vpc_cidr_block_associations" {
  description = "Secondary VPC CIDR association IDs (one per secondary_vpc_cidrs entry)."
  value       = aws_vpc_ipv4_cidr_block_association.secondary[*].id
}
