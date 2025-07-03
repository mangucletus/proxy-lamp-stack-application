terraform {
  required_version = ">= 1.0" # Ensure Terraform version compatibility
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # Use AWS provider v5.x
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
  backend "s3" {
    bucket = "proxy-lamp-stack-tfstate-cletusmangu-1749764" # Remote state storage bucket (UNCHANGED as requested)
    key    = "proxy-lamp-stack/terraform.tfstate"           # Updated path to store the state file
    region = "eu-central-1"                                 # Updated region
  }
}

provider "aws" {
  region = var.aws_region # Use variable for region flexibility
}

provider "random" {}

# Generate unique suffix for resource naming to avoid conflicts
resource "random_id" "deployment_id" {
  byte_length = 4
}

locals {
  # Unique naming convention for this deployment
  deployment_suffix = random_id.deployment_id.hex
  common_tags = {
    Project     = "proxy-lamp-stack"
    Environment = "production"
    DeployedBy  = "terraform"
    Timestamp   = timestamp()
  }
}

# VPC Module - Network Infrastructure
module "vpc" {
  source = "./modules/vpc"

  aws_region        = var.aws_region
  deployment_suffix = local.deployment_suffix
  tags              = local.common_tags
}

# Security Module - Security Groups for different tiers
module "security" {
  source = "./modules/security"

  vpc_id             = module.vpc.vpc_id
  deployment_suffix  = local.deployment_suffix
  tags               = local.common_tags
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids
}

# Database Module - RDS MySQL for scalable database tier
module "database" {
  source = "./modules/database"

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  database_sg_id     = module.security.database_sg_id
  db_password        = var.db_password
  deployment_suffix  = local.deployment_suffix
  tags               = local.common_tags

  enable_performance_insights = false #disable Performance Insights sice db.t3.micro doesn't support it
}

# Load Balancer Module - Application Load Balancer for high availability
module "load_balancer" {
  source = "./modules/load_balancer"

  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  alb_sg_id         = module.security.alb_sg_id
  deployment_suffix = local.deployment_suffix
  tags              = local.common_tags
}

# Compute Module - Auto Scaling Group with EC2 instances
module "compute" {
  source = "./modules/compute"

  aws_region        = var.aws_region
  instance_type     = var.instance_type
  key_name          = var.key_name
  public_key        = var.public_key
  public_subnet_ids = module.vpc.public_subnet_ids
  web_sg_id         = module.security.web_sg_id
  target_group_arn  = module.load_balancer.target_group_arn
  db_endpoint       = module.database.db_endpoint
  db_password       = var.db_password
  deployment_suffix = local.deployment_suffix
  tags              = local.common_tags

  depends_on = [module.database]
}

# Monitoring Module - CloudWatch monitoring and observability
module "monitoring" {
  source = "./modules/monitoring"

  load_balancer_arn_suffix = module.load_balancer.load_balancer_arn_suffix
  target_group_arn_suffix  = module.load_balancer.target_group_arn_suffix
  autoscaling_group_name   = module.compute.autoscaling_group_name
  db_instance_identifier   = module.database.db_instance_identifier
  deployment_suffix        = local.deployment_suffix
  tags                     = local.common_tags

}