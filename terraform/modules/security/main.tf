# Security Group for Application Load Balancer
resource "aws_security_group" "proxy_lamp_alb_sg" {
  name        = "proxy-lamp-alb-sg-${var.deployment_suffix}"
  description = "Security group for Application Load Balancer"
  vpc_id      = var.vpc_id

  # Allow HTTP from anywhere
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTPS from anywhere
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "proxy-lamp-alb-sg-${var.deployment_suffix}"
    Tier = "Load Balancer"
  })
}

# Security Group for Web Servers (EC2 instances)
resource "aws_security_group" "proxy_lamp_web_sg" {
  name        = "proxy-lamp-web-sg-${var.deployment_suffix}"
  description = "Security group for web servers behind load balancer"
  vpc_id      = var.vpc_id

  # Allow SSH from anywhere (restrict this in production to your IP)
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # TODO: Restrict to specific IPs in production
  }

  # Allow HTTP from Load Balancer only
  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.proxy_lamp_alb_sg.id]
  }

  # Allow HTTPS from Load Balancer only
  ingress {
    description     = "HTTPS from ALB"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.proxy_lamp_alb_sg.id]
  }

  # Allow Apache server-status monitoring from within VPC
  ingress {
    description = "Apache server-status"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # Allow all outbound traffic (for package updates, CloudWatch, etc.)
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "proxy-lamp-web-sg-${var.deployment_suffix}"
    Tier = "Web"
  })
}

# Security Group for RDS Database
resource "aws_security_group" "proxy_lamp_db_sg" {
  name        = "proxy-lamp-db-sg-${var.deployment_suffix}"
  description = "Security group for RDS MySQL database"
  vpc_id      = var.vpc_id

  # Allow MySQL from web servers only
  ingress {
    description     = "MySQL from web servers"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.proxy_lamp_web_sg.id]
  }

  # Allow MySQL from within VPC for maintenance
  ingress {
    description = "MySQL from VPC"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # Allow outbound traffic for updates and monitoring
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "proxy-lamp-db-sg-${var.deployment_suffix}"
    Tier = "Database"
  })
}

# Security Group for VPC Endpoints (optional)
resource "aws_security_group" "proxy_lamp_endpoint_sg" {
  name        = "proxy-lamp-endpoint-sg-${var.deployment_suffix}"
  description = "Security group for VPC endpoints"
  vpc_id      = var.vpc_id

  # Allow HTTPS from VPC
  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # Allow outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "proxy-lamp-endpoint-sg-${var.deployment_suffix}"
    Tier = "VPC Endpoints"
  })
}

# Security Group for CloudWatch monitoring agents
resource "aws_security_group" "proxy_lamp_monitoring_sg" {
  name        = "proxy-lamp-monitoring-sg-${var.deployment_suffix}"
  description = "Security group for monitoring and observability"
  vpc_id      = var.vpc_id

  # Allow CloudWatch agent communication
  ingress {
    description = "CloudWatch metrics"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # Allow custom metrics collection
  ingress {
    description = "Custom metrics"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # Allow outbound traffic for metric publishing
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "proxy-lamp-monitoring-sg-${var.deployment_suffix}"
    Tier = "Monitoring"
  })
}

# Network ACL for additional security (optional but recommended)
resource "aws_network_acl" "proxy_lamp_web_nacl" {
  vpc_id     = var.vpc_id
  subnet_ids = var.public_subnet_ids

  # Allow HTTP inbound
  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }

  # Allow HTTPS inbound
  ingress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  # Allow SSH inbound (restrict in production)
  ingress {
    protocol   = "tcp"
    rule_no    = 120
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 22
    to_port    = 22
  }

  # Allow ephemeral ports inbound
  ingress {
    protocol   = "tcp"
    rule_no    = 130
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # Allow all outbound
  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = merge(var.tags, {
    Name = "proxy-lamp-web-nacl-${var.deployment_suffix}"
  })
}

# Network ACL for database subnets
resource "aws_network_acl" "proxy_lamp_db_nacl" {
  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  # Allow MySQL from web subnets
  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "10.0.1.0/24"  # Public subnet 1
    from_port  = 3306
    to_port    = 3306
  }

  ingress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = "10.0.2.0/24"  # Public subnet 2
    from_port  = 3306
    to_port    = 3306
  }

  # Allow ephemeral ports for return traffic
  ingress {
    protocol   = "tcp"
    rule_no    = 120
    action     = "allow"
    cidr_block = "10.0.0.0/16"
    from_port  = 1024
    to_port    = 65535
  }

  # Allow outbound for updates and monitoring
  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = merge(var.tags, {
    Name = "proxy-lamp-db-nacl-${var.deployment_suffix}"
  })
}