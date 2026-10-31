
# AWS Free Tier budget alert
budget_email  = "kalosora@outlook.com"
budget_start  = "2026-10-28_00:00"
budget_end    = "2027-04-10_23:59"
budget_amount = 200
budget_unit   = "USD"

### AWS resources
aws_account_id = "823058656952"
aws_region     = "ap-southeast-1"
aws_env        = "dev"
cidr_block     = "10.0.0.0/16"

availability_zones = [
  "ap-southeast-1a",
  "ap-southeast-1b",
  "ap-southeast-1c",
]

# EKS variable
eks_kubernetes_version         = "1.35"
eks_admin_principal_arn        = "arn:aws:iam::823058656952:role/AWS-InfraDevOps"
eks_public_access_cidrs        = ["103.151.172.76/32"]
eks_node_instance_types        = ["t3.small"]
eks_require_free_tier_eligible = true
eks_node_scaling = {
  min_size     = 1
  desired_size = 2
  max_size     = 3
}

# Private AWS API connectivity; S3 Gateway endpoint is enabled separately.
vpc_endpoint_interface_services = [
  # "ssm",
  # "ssmmessages",
  # "ec2",
  # "ebs",
  # "elasticfilesystem",
  # "logs",
  # "monitoring",
  # "ecr.api",
  # "ecr.dkr",
  # "sts",
  # "eks",
  # "eks-auth",
]

# Single shared AL2023 NAT instance in the first configured public subnet.
nat_instance_type = "t4g.micro"
# nat_instance_ami_id = "ami-0f3e7b8c1e5d2a1b2" # By default will get the latest AL2023 AMI for the region.
