# Standard EKS Module

Creates an EKS control plane and an EC2 managed node group using native AWS Terraform resources. EKS Auto Mode is not enabled.

- Requires Terraform >= 1.5.7 and AWS Provider ~> 6.0. The caller configures the AWS region and credentials.
- Defaults to two `t3.medium` nodes running AL2023 x86_64, with a capacity range of 1–3 nodes.
- Uses an EKS access entry with an explicitly specified IAM role or user ARN for cluster administrator access.
- Installs managed VPC CNI, CoreDNS, and kube-proxy add-ons. AWS selects compatible default add-on versions at creation time.
- The API endpoint is private by default. Public access can be enabled for specified CIDRs.

## Network Prerequisites

Provide private subnets in at least two Availability Zones within the same VPC. The VPC must have DNS support and DNS hostnames enabled.
Nodes need access to ECR, S3, and AWS APIs through a NAT Gateway. Alternatively, configure all required VPC endpoints, private DNS, and security group rules.

The root configuration now connects `module.vpc_endpoint` to the private subnets and makes EKS depend on it. This provides private connectivity to the configured AWS services without NAT. See [the VPC endpoint module](../vpc_endpoint/README.md) for the service list and limitations. External image registries and other internet destinations remain unreachable until NAT or another egress path is added.

With a private-only API endpoint, run kubectl inside the VPC or connect through VPN, Direct Connect, or another private connection. Security group rules must allow TCP port 443 from the client to the control plane.

## Usage in the Existing Root Module

The root configuration already calls this module. The following example shows the required inputs; replace the placeholder ARN and CIDR when adapting it:

```hcl
module "eks" {
  source = "./eks"

  depends_on = [module.vpc_endpoint]

  cluster_name       = "${var.aws_env}-eks"
  kubernetes_version = "1.35"
  private_subnet_ids = module.vpc.private_subnet_ids

  admin_principal_arn = "arn:aws:iam::123456789012:role/EKSAdmin"

  # To connect from your computer, enable the public API and specify your public egress IP.
  endpoint_public_access       = true
  endpoint_public_access_cidrs = ["203.0.113.10/32"]

  instance_types = ["t3.medium"]
  capacity_type  = "ON_DEMAND"
  node_scaling = {
    min_size     = 1
    desired_size = 2
    max_size     = 3
  }

  tags = {
    Environment = var.aws_env
    ManagedBy   = "Terraform"
  }
}
```

`admin_principal_arn` must identify an existing IAM role or user. Do not use an `assumed-role` session ARN returned by `aws sts get-caller-identity`. Connect using AWS credentials for the configured administrator identity; the identity running Terraform does not automatically receive Kubernetes administrator permissions.

```bash
cd modules
terraform init -backend-config="dev.s3.tfbackend"
terraform validate
terraform plan -var-file="dev.tfvars" -out=eks.tfplan
terraform apply eks.tfplan

# Use the administrator identity configured above and the correct cluster region and name.
aws eks update-kubeconfig --region ap-southeast-1 --name dev-eks
kubectl get nodes
kubectl get pods -n kube-system
```

The full plan also includes resources managed by the same root module, such as the VPC and budget. Review the plan before applying it.

## Behavior and Limitations

`max_size` defines the capacity limit; it does not automatically scale nodes based on Pod demand. Install Cluster Autoscaler separately if needed.
Terraform manages `desired_size`. The next apply will revert changes made by manual scaling.
To keep the example simple, VPC CNI permissions are attached to the node IAM role. For production, consider a dedicated IRSA or Pod Identity role.
This module does not install the EBS CSI Driver, AWS Load Balancer Controller, or an Ingress controller. Configure persistent volumes and Ingress separately as needed.

The EKS control plane, EC2 instances, disks, and networking resources such as NAT Gateways incur charges. Before cleanup, delete load balancers and storage created by workloads, then destroy the corresponding resources through the calling Terraform configuration. Running `terraform destroy` in the root module also deletes the VPC and budget resources managed by that root module.

References: [AWS Provider EKS cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_cluster), [Managed node group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_node_group).
