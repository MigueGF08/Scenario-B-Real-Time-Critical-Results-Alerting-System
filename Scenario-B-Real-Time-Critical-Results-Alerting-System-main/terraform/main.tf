# Configuración principal y provider
# main.tf - Configuración principal de Terraform

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }

  # Opcional: Backend para almacenar el state en S3
  # backend "s3" {
  #   bucket         = "critalert-terraform-state"
  #   key            = "critalert/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  # }
}

# Provider de AWS
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "CritAlert"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = var.project_owner
    }
  }
}

# Data source para obtener la cuenta de AWS actual
data "aws_caller_identity" "current" {}

# Data source para obtener la región actual
data "aws_region" "current" {}

# Locals para valores reutilizables
locals {
  project_name = "critalert"
  
  # Prefijo para nombres de recursos
  name_prefix = "${local.project_name}-${var.environment}"
  
  # Account ID y región
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  
  # Tags comunes
  common_tags = {
    Project     = "CritAlert"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}