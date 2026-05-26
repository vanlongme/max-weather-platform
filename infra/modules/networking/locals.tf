locals {
  cluster_tag_value = var.eks_cluster_name == "" ? var.name : var.eks_cluster_name

  create_igw = length(var.public_subnet_cidrs) > 0

  vpc_endpoint_subnet_ids = length(aws_subnet.private) > 0 ? aws_subnet.private[*].id : aws_subnet.public[*].id

  vpc_endpoint_route_table_ids = compact([
    length(aws_route_table.private) > 0 ? aws_route_table.private[0].id : "",
    length(aws_route_table.public) > 0 ? aws_route_table.public[0].id : "",
  ])
}
