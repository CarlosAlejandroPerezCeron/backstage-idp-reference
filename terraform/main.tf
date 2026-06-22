terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
  backend "s3" {
    bucket         = "infravix-terraform-state"
    key            = "idp/eks-cluster/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = "backstage-idp"
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = "platform-engineering"
    }
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = var.environment != "production"
  enable_dns_hostnames = true

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    "kubernetes.io/role/internal-elb"            = "1"
    "karpenter.sh/discovery"                     = var.cluster_name
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.29"

  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets
  cluster_endpoint_public_access = false

  cluster_encryption_config = {
    resources = ["secrets"]
  }

  eks_managed_node_groups = {
    platform = {
      instance_types = ["m6i.large"]
      capacity_type  = "ON_DEMAND"
      min_size       = 2
      max_size       = 4
      desired_size   = 2

      labels = {
        role = "platform"
      }
    }
  }

  # Karpenter for workload nodes
  enable_karpenter = true
  karpenter = {
    chart_version = "0.35.0"
  }
}

# RDS for Backstage catalog
module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 6.0"

  identifier = "${var.cluster_name}-backstage"
  engine     = "postgres"
  engine_version = "15.4"
  instance_class = "db.t3.medium"
  allocated_storage = 20

  db_name  = "backstage"
  username = "backstage"
  manage_master_user_password = true

  multi_az               = var.environment == "production"
  storage_encrypted      = true
  deletion_protection    = var.environment == "production"

  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = module.vpc.database_subnet_group
}
