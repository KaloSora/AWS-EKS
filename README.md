# AWS-EKS

## Terraform Runbook
| Step | Command | Description |
| :--- | :--- | :--- |
| 1 | `terraform init -backend-config="dev.s3.tfbackend"` | Terraform initialization with backend S3 bucket |
| 2 | `terraform apply -target=module.budget_alert -var-file="dev.tfvars"` | Create AWS VPC |
| 3 | `terraform apply -target=module.vpc -var-file="dev.tfvars"` | Create AWS VPC |