# AWS-EKS

## Terraform Runbook
| Step | Command | Description |
| :--- | :--- | :--- |
| 1 | `terraform init -backend-config="dev.s3.tfbackend"` | Terraform initialization with backend S3 bucket |
| 2 | `terraform apply -target=module.budget_alert -var-file="dev.tfvars"` | Create AWS VPC |
| 3 | `terraform apply -target=module.route53 -var-file="dev.tfvars"` | Create AWS Hosted Zone |
| 4 | `terraform apply -target=module.vpc -var-file="dev.tfvars"` | Create AWS VPC |
| 5 | `terraform apply -target=module.vpc_endpoint -var-file="dev.tfvars"` | Create VPC S3 Gateway endpoint only. |
| 6 | `terraform apply -target=module.ec2_nat_instance -var-file="dev.tfvars"` | Create NAT resources only when `nat_instance_enable = true`. |
| 7 | `terraform apply -target=module.eks -var-file="dev.tfvars"` | Create EKS |
| 8 | `terraform apply -target=module.eks_efs -var-file="dev.tfvars"` | Create AWS EFS |
| 9 | `terraform apply -target=module.eks_storage -var-file="dev.tfvars"` | Create AWS Storage for EFS and EBS |
| 10 | `terraform apply -target=module.eks_ingress -var-file="dev.tfvars"` | Create AWS EKS Ingress |

## Reference
[Learn AWS EKS](https://docs.aws.amazon.com/eks/latest/userguide/learn-eks.html)