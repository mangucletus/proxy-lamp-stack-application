# Create a VPC for the Proxy LAMP stack with load balancer support
resource "aws_vpc" "proxy_lamp_vpc" {
  cidr_block           = "10.0.0.0/16"      # Large IP range for scalability
  enable_dns_hostnames = true              # Enable DNS for instances
  enable_dns_support   = true              # Required for hostname resolution
  
  tags = merge(var.tags, {
    Name = "proxy-lamp-vpc-${var.deployment_suffix}"
  })
}

# Internet Gateway to allow internet access
resource "aws_internet_gateway" "proxy_lamp_igw" {
  vpc_id = aws_vpc.proxy_lamp_vpc.id
  
  tags = merge(var.tags, {
    Name = "proxy-lamp-igw-${var.deployment_suffix}"
  })
}

# Data source to get available AZs
data "aws_availability_zones" "available" {
  state = "available"
}

# Public subnets for load balancer and NAT gateways (Multi-AZ)
resource "aws_subnet" "proxy_lamp_public_subnets" {
  count = 2  # Create 2 public subnets for high availability
  
  vpc_id                  = aws_vpc.proxy_lamp_vpc.id
  cidr_block              = "10.0.${count.index + 1}.0/24"               # 10.0.1.0/24, 10.0.2.0/24
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true                        # Auto-assign public IP
  
  tags = merge(var.tags, {
    Name = "proxy-lamp-public-subnet-${count.index + 1}-${var.deployment_suffix}"
    Type = "Public"
  })
}

# Private subnets for database and future private resources (Multi-AZ)
resource "aws_subnet" "proxy_lamp_private_subnets" {
  count = 2  # Create 2 private subnets for high availability
  
  vpc_id            = aws_vpc.proxy_lamp_vpc.id
  cidr_block        = "10.0.${count.index + 10}.0/24"               # 10.0.10.0/24, 10.0.11.0/24
  availability_zone = data.aws_availability_zones.available.names[count.index]
  
  tags = merge(var.tags, {
    Name = "proxy-lamp-private-subnet-${count.index + 1}-${var.deployment_suffix}"
    Type = "Private"
  })
}

# Elastic IPs for NAT Gateways
resource "aws_eip" "proxy_lamp_nat_eips" {
  count = 2  # One for each AZ
  
  domain = "vpc"
  
  tags = merge(var.tags, {
    Name = "proxy-lamp-nat-eip-${count.index + 1}-${var.deployment_suffix}"
  })
  
  depends_on = [aws_internet_gateway.proxy_lamp_igw]
}

# NAT Gateways for private subnet internet access
resource "aws_nat_gateway" "proxy_lamp_nat_gateways" {
  count = 2  # One for each AZ
  
  allocation_id = aws_eip.proxy_lamp_nat_eips[count.index].id
  subnet_id     = aws_subnet.proxy_lamp_public_subnets[count.index].id
  
  tags = merge(var.tags, {
    Name = "proxy-lamp-nat-gateway-${count.index + 1}-${var.deployment_suffix}"
  })
  
  depends_on = [aws_internet_gateway.proxy_lamp_igw]
}

# Public route table to direct traffic to internet
resource "aws_route_table" "proxy_lamp_public_rt" {
  vpc_id = aws_vpc.proxy_lamp_vpc.id
  
  route {
    cidr_block = "0.0.0.0/0"                  # Default route
    gateway_id = aws_internet_gateway.proxy_lamp_igw.id
  }
  
  tags = merge(var.tags, {
    Name = "proxy-lamp-public-route-table-${var.deployment_suffix}"
  })
}

# Private route tables (one per AZ)
resource "aws_route_table" "proxy_lamp_private_rts" {
  count = 2
  
  vpc_id = aws_vpc.proxy_lamp_vpc.id
  
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.proxy_lamp_nat_gateways[count.index].id
  }
  
  tags = merge(var.tags, {
    Name = "proxy-lamp-private-route-table-${count.index + 1}-${var.deployment_suffix}"
  })
}

# Associate public route table with public subnets
resource "aws_route_table_association" "proxy_lamp_public_rta" {
  count = 2
  
  subnet_id      = aws_subnet.proxy_lamp_public_subnets[count.index].id
  route_table_id = aws_route_table.proxy_lamp_public_rt.id
}

# Associate private route tables with private subnets
resource "aws_route_table_association" "proxy_lamp_private_rta" {
  count = 2
  
  subnet_id      = aws_subnet.proxy_lamp_private_subnets[count.index].id
  route_table_id = aws_route_table.proxy_lamp_private_rts[count.index].id
}

# VPC Flow Logs for monitoring and security
resource "aws_flow_log" "proxy_lamp_vpc_flow_log" {
  iam_role_arn    = aws_iam_role.flow_log_role.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_log.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.proxy_lamp_vpc.id
  
  tags = merge(var.tags, {
    Name = "proxy-lamp-vpc-flow-log-${var.deployment_suffix}"
  })
}

# CloudWatch Log Group for VPC Flow Logs
resource "aws_cloudwatch_log_group" "vpc_flow_log" {
  name              = "/aws/vpc/proxy-lamp-flow-logs-${var.deployment_suffix}"
  retention_in_days = 14
  
  tags = var.tags
}

# IAM role for VPC Flow Logs
resource "aws_iam_role" "flow_log_role" {
  name = "proxy-lamp-flow-log-role-${var.deployment_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })
  
  tags = var.tags
}

# IAM policy for VPC Flow Logs
resource "aws_iam_role_policy" "flow_log_policy" {
  name = "proxy-lamp-flow-log-policy-${var.deployment_suffix}"
  role = aws_iam_role.flow_log_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

# VPC Endpoints for secure AWS service access (optional, for cost optimization)
resource "aws_vpc_endpoint" "s3_endpoint" {
  vpc_id            = aws_vpc.proxy_lamp_vpc.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  
  route_table_ids = [
    aws_route_table.proxy_lamp_public_rt.id,
    aws_route_table.proxy_lamp_private_rts[0].id,
    aws_route_table.proxy_lamp_private_rts[1].id
  ]
  
  tags = merge(var.tags, {
    Name = "proxy-lamp-s3-endpoint-${var.deployment_suffix}"
  })
}