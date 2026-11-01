# AWS-EKS

## Terraform Runbook
| Step | Command | Description |
| :--- | :--- | :--- |
| 1 | `terraform init -backend-config="dev.s3.tfbackend"` | Terraform initialization with backend S3 bucket |
| 2 | `terraform apply -target=module.budget_alert -var-file="dev.tfvars"` | Create AWS VPC |
| 3 | `terraform apply -target=module.vpc -var-file="dev.tfvars"` | Create AWS VPC |
| 4 | `terraform apply -target=module.vpc_endpoint -var-file="dev.tfvars"` | Create VPC S3 Gateway endpoint only. |
| 5 | `terraform apply -target=module.ec2_nat_instance -var-file="dev.tfvars"` | Create NAT resources only when `nat_instance_enable = true`. |
| 6 | `terraform apply -target=module.eks -var-file="dev.tfvars"` | Create EKS |

`nat_instance_enable` defaults to `true`, but `modules/dev.tfvars` temporarily sets it to `false` for initial configuration validation. Private nodes still require NAT or suitable VPC endpoints for AWS API calls and image pulls. The current empty Interface endpoint list and S3 Gateway endpoint alone are insufficient for a functioning private node group. Restore connectivity before running the EKS deployment step. Setting the flag to `false` for an existing NAT plans its deletion and removes private default routes; review the plan before applying. See [NAT configuration](modules/ec2_nat_instance/README.md#temporarily-disabling-nat).
