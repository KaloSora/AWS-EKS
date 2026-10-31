# AWS-EKS

## Terraform Runbook
| Step | Command | Description |
| :--- | :--- | :--- |
| 1 | `terraform init -backend-config="dev.s3.tfbackend"` | Terraform initialization with backend S3 bucket |
| 2 | `terraform apply -target=module.budget_alert -var-file="dev.tfvars"` | Create AWS VPC |
| 3 | `terraform apply -target=module.vpc -var-file="dev.tfvars"` | Create AWS VPC |
| 4 | `terraform apply -target=module.vpc_endpoint -var-file="dev.tfvars"` | Create VPC S3 Gateway endpoint only. |
| 5 | `terraform apply -target=module.ec2_nat_instance -var-file="dev.tfvars"` | Create NAT instance for Internet traffic for cost saving. |
| 6 | `terraform apply -target=module.eks -var-file="dev.tfvars"` | Create EKS |