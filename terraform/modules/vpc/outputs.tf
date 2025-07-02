output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.proxy_lamp_vpc.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.proxy_lamp_vpc.cidr_block
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.proxy_lamp_igw.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.proxy_lamp_public_subnets[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.proxy_lamp_private_subnets[*].id
}

output "public_subnet_cidrs" {
  description = "CIDR blocks of the public subnets"
  value       = aws_subnet.proxy_lamp_public_subnets[*].cidr_block
}

output "private_subnet_cidrs" {
  description = "CIDR blocks of the private subnets"
  value       = aws_subnet.proxy_lamp_private_subnets[*].cidr_block
}

output "availability_zones" {
  description = "Availability zones of the subnets"
  value       = aws_subnet.proxy_lamp_public_subnets[*].availability_zone
}

output "nat_gateway_ids" {
  description = "IDs of the NAT Gateways"
  value       = aws_nat_gateway.proxy_lamp_nat_gateways[*].id
}

output "nat_gateway_ips" {
  description = "Public IPs of the NAT Gateways"
  value       = aws_eip.proxy_lamp_nat_eips[*].public_ip
}

output "public_route_table_id" {
  description = "ID of the public route table"
  value       = aws_route_table.proxy_lamp_public_rt.id
}

output "private_route_table_ids" {
  description = "IDs of the private route tables"
  value       = aws_route_table.proxy_lamp_private_rts[*].id
}

output "vpc_flow_log_id" {
  description = "ID of the VPC Flow Log"
  value       = aws_flow_log.proxy_lamp_vpc_flow_log.id
}

output "vpc_flow_log_group_name" {
  description = "Name of the VPC Flow Log CloudWatch Log Group"
  value       = aws_cloudwatch_log_group.vpc_flow_log.name
}

output "s3_vpc_endpoint_id" {
  description = "ID of the S3 VPC Endpoint"
  value       = aws_vpc_endpoint.s3_endpoint.id
}