# terraform/main.tf - CHECK THESE SECTIONS

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
  backend "s3" {
    bucket = "proxy-lamp-stack-tfstate-cletusmangu-1749764"
    key    = "proxy-lamp-stack/terraform.tfstate"
    region = "eu-central-1"
  }
}

provider "aws" {
  region = var.aws_region
}

provider "random" {}

# Generate unique suffix for resource naming
resource "random_id" "deployment_id" {
  byte_length = 4
}

locals {
  deployment_suffix = random_id.deployment_id.hex
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    DeployedBy  = "terraform"
    Timestamp   = timestamp()
  }
}

# VPC Module
module "vpc" {
  source = "./modules/vpc"

  aws_region        = var.aws_region
  deployment_suffix = local.deployment_suffix
  tags              = local.common_tags
}

# Security Module
module "security" {
  source = "./modules/security"

  vpc_id             = module.vpc.vpc_id
  deployment_suffix  = local.deployment_suffix
  tags               = local.common_tags
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids
}

# Database Module
module "database" {
  source = "./modules/database"

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  database_sg_id     = module.security.database_sg_id
  db_password        = var.db_password
  deployment_suffix  = local.deployment_suffix
  tags               = local.common_tags
  db_instance_class  = var.db_instance_class
}

# Load Balancer Module
module "load_balancer" {
  source = "./modules/load_balancer"

  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  alb_sg_id         = module.security.alb_sg_id
  deployment_suffix = local.deployment_suffix
  tags              = local.common_tags

  # Health check variables
  health_check_path     = var.health_check_path
  health_check_interval = var.health_check_interval
  health_check_timeout  = var.health_check_timeout
  healthy_threshold     = var.healthy_threshold
  unhealthy_threshold   = var.unhealthy_threshold
}

# Compute Module
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

  # Auto Scaling variables
  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  depends_on = [module.database]
}

# Monitoring Module
module "monitoring" {
  source = "./modules/monitoring"

  load_balancer_arn_suffix = module.load_balancer.load_balancer_arn_suffix
  target_group_arn_suffix  = module.load_balancer.target_group_arn_suffix
  autoscaling_group_name   = module.compute.autoscaling_group_name
  db_instance_identifier   = module.database.db_instance_identifier
  deployment_suffix        = local.deployment_suffix
  tags                     = local.common_tags
}