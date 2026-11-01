terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }

  backend "s3" {
    key     = "eks/dev/terraform.tfstate"
    encrypt = true
  }
}

provider "aws" {
  region = var.aws_region
}

provider "helm" {
  kubernetes = {
    config_path = abspath("${path.root}/${var.eks_kubeconfig_file}")
    config_context = "${var.aws_env}-eks"
  }
}
