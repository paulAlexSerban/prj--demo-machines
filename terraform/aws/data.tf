# Ubuntu 24.04 (Noble) amd64 published by Canonical (account 099720109477).
# Prefix matches Canonical's published gp3 Noble name (locator type hvm:ebs-ssd-gp3).
# UNVERIFIED against DescribeImages from this machine. The eight ? characters are the
# date suffix (locator serials are 8 digits, for example 20260828) so "server-minimal-..." is excluded.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-????????"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

# The default VPC in var.region. This phase does not create a network.
# If the region has no default VPC, plan fails here. Stop and ask; do not add a VPC module.
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}
