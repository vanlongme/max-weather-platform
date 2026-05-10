output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "List of IDs of the public subnets (one per AZ)."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of IDs of the private subnets (one per AZ)."
  value       = aws_subnet.private[*].id
}

output "nat_gateway_id" {
  description = "ID of the first (or only) NAT Gateway."
  value       = aws_nat_gateway.main[0].id
}

output "nat_gateway_public_ip" {
  description = "Public IP address of the first (or only) NAT Gateway EIP."
  value       = aws_eip.nat[0].public_ip
}

output "public_route_table_id" {
  description = "ID of the public route table."
  value       = aws_route_table.public.id
}

output "private_route_table_ids" {
  description = "List of private route table IDs (one per AZ)."
  value       = aws_route_table.private[*].id
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway attached to the VPC."
  value       = aws_internet_gateway.main.id
}
