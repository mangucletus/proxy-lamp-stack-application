#!/bin/bash

# Terraform State Migration Script
# Run this BEFORE applying the modularized configuration

echo "Starting Terraform state migration..."

# VPC Module Resources
echo "Moving VPC resources..."
terraform state mv aws_vpc.lamp_vpc module.vpc.aws_vpc.lamp_vpc
terraform state mv aws_internet_gateway.lamp_igw module.vpc.aws_internet_gateway.lamp_igw
terraform state mv aws_subnet.lamp_public_subnet module.vpc.aws_subnet.lamp_public_subnet
terraform state mv aws_route_table.lamp_public_rt module.vpc.aws_route_table.lamp_public_rt
terraform state mv aws_route_table_association.lamp_public_rta module.vpc.aws_route_table_association.lamp_public_rta

# Security Module Resources
echo "Moving Security resources..."
terraform state mv aws_security_group.lamp_sg module.security.aws_security_group.lamp_sg

# Compute Module Resources
echo "Moving Compute resources..."
terraform state mv aws_key_pair.lamp_keypair module.compute.aws_key_pair.lamp_keypair
terraform state mv aws_instance.lamp_server module.compute.aws_instance.lamp_server
terraform state mv aws_eip.lamp_eip module.compute.aws_eip.lamp_eip

echo "State migration completed!"
echo "Now you can safely run: terraform plan"