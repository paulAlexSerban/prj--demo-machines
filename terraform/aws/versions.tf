terraform {
  required_version = "1.16.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.68.0"
    }
  }

  # Path is per profile, passed at init:
  # terraform init -backend-config="path=../../state/aws-<profile>.tfstate"
  backend "local" {}
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      "managed-by" = "demo-machines"
      owner        = var.owner
      expires_at   = var.expires_at
    }
  }
}
