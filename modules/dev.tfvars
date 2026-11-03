
# AWS Free Tier budget alert
budget_email  = "kalosora@outlook.com"
budget_start  = "2026-10-28_00:00"
budget_end    = "2027-04-10_23:59"
budget_amount = 200
budget_unit   = "USD"

# Hosted Zone for AWS
# Namecheap domain expires on Nov 2, 2027
hosted_zone_name = "kalosora.live"

# ACM certificate also covers first-level subdomains.
acm_subject_alternative_names = ["*.kalosora.live"]

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
eks_kubernetes_version         = "1.36"
eks_admin_principal_arn        = "arn:aws:iam::823058656952:role/AWS-InfraDevOps"
eks_public_access_cidrs        = ["103.151.172.76/32"]
eks_node_instance_types        = ["t3.small"]
eks_require_free_tier_eligible = true
eks_node_scaling = {
  min_size     = 1
  desired_size = 3
  max_size     = 5
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
nat_instance_enable = true
nat_instance_type   = "t4g.micro"
# nat_instance_ami_id = "ami-0f3e7b8c1e5d2a1b2" # By default will get the latest AL2023 AMI for the region.

eks_csi_enabled = true
csi_addon_versions = {
  ebs = "v1.67.2-eksbuild.1"
  efs = "v3.5.3-eksbuild.1"
}

eks_kubeconfig_file = "eks_kubeconfig/config"

# AWS Load Balancer Controller; deploy after EKS and local kubeconfig setup.
# Reuses the cluster IAM OIDC provider configured with eks_csi_enabled=true.
eks_ingress_chart_version = "3.6.2"
eks_ingress_replica_count = 1 # Set it to 1 for Free Tier eligibility; >= 2 is recommended for HA.

# Regional EFS is retained across targeted EKS teardown/recreation.
eks_efs_file_system_name = "dev-eks-efs"
eks_efs_throughput_mode  = "bursting"

eks_components = {
  argocd = {
    enabled         = true
    release_name    = "argocd"
    namespace       = "argocd"
    repository      = "https://argoproj.github.io/argo-helm"
    chart           = "argo-cd"
    version         = "10.10.3"
    timeout         = 600
    atomic          = true
    wait            = true
    wait_for_jobs   = false
    value_templates = ["argocd.yaml"]
    config = {
      argocd_url            = "argocd.core.com"
      argocd_admin_password = "ArgoCD12345"
    }
  }
}
