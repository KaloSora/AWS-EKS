# Standard EKS Module

Creates an EKS control plane and an EC2 managed node group using native AWS Terraform resources. EKS Auto Mode is not enabled.

- Requires Terraform >= 1.5.7 and AWS Provider ~> 6.0. The caller configures the AWS region and credentials.
- Defaults to two `t3.small` nodes running AL2023 x86_64, with a capacity range of 1–3 nodes.
- Uses an EKS access entry with an explicitly specified IAM role or user ARN for cluster administrator access.
- Installs managed VPC CNI, CoreDNS, and kube-proxy add-ons. AWS selects compatible default add-on versions at creation time.
- The API endpoint is private by default. Public access can be enabled for specified CIDRs.

## Network Prerequisites

Provide private subnets in at least two Availability Zones within the same VPC. The VPC must have DNS support and DNS hostnames enabled.
Nodes need access to ECR, S3, and AWS APIs through a NAT Gateway. Alternatively, configure all required VPC endpoints, private DNS, and security group rules.

The root configuration now connects a shared [EC2 NAT instance](../ec2_nat_instance/README.md) to the private subnet default routes. EKS depends on the NAT module and the instance-type preflight resource. The S3 Gateway endpoint is configured separately. The development configuration disables paid Interface endpoints; AWS public APIs and external image registries are reached through NAT. Nodes keep private addresses. Confirm NAT cloud-init has completed before starting nodes; a running EC2 instance alone does not prove NAT is ready.

With a private-only API endpoint, run kubectl inside the VPC or connect through VPN, Direct Connect, or another private connection. Security group rules must allow TCP port 443 from the client to the control plane.

## Usage in the Existing Root Module

The root configuration already calls this module. The following example shows the required inputs; replace the placeholder ARN and CIDR when adapting it:

```hcl
module "eks" {
  source = "./eks"

  depends_on = [terraform_data.eks_preflight, module.ec2_nat_instance]

  cluster_name       = "${var.aws_env}-eks"
  kubernetes_version = "1.35"
  private_subnet_ids = module.vpc.private_subnet_ids

  admin_principal_arn = "arn:aws:iam::123456789012:role/EKSAdmin"

  # To connect from your computer, enable the public API and specify your public egress IP.
  endpoint_public_access       = true
  endpoint_public_access_cidrs = ["203.0.113.10/32"]

  instance_types             = ["t3.small"]
  require_free_tier_eligible = true
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

## Instance-Type Preflight

The development configuration uses `t3.small` and `eks_require_free_tier_eligible = true`. The root `eks_preflight.tf` queries EC2 in the selected region for the requested types, the x86_64 architecture required by the node AMI, and (when enabled) the `free-tier-eligible` flag. A lifecycle precondition rejects the entire selection if any requested type is missing. The lookup is outside `module.eks`, so the NAT dependency cannot defer this root check until infrastructure creation. The module also checks types when used independently.

The standalone module defaults `require_free_tier_eligible` to false; the project root enables it by default. Set it to false only when your account plan allows the desired paid types. Free Tier eligibility is not a price guarantee and does not validate account credits, vCPU quotas, IAM permissions, or capacity in each AZ. EC2 can still reject an otherwise compatible launch. The Terraform identity needs `ec2:DescribeInstanceTypes`.

## Failure Recovery and Safe Teardown

Use `script/run_infra_create.sh` and `script/run_infra_destroy.sh` from the project root. Their shared read-only checks compare AWS node groups with node groups recorded in the current Terraform state before any apply/destroy. They stop if an AWS node group is untracked, or if state/AWS queries fail. Check account, region, backend and workspace before resolving a mismatch. Do not automatically remove state or run a full apply over leftover resources.

The destroy script first destroys the managed node group (and Terraform dependents such as CoreDNS), then waits for AWS to report its deletion. It rechecks that no node groups remain before destroying the EKS cluster and IAM roles. NAT is removed last. A destroy/wait failure stops subsequent steps. The destroy script displays its scope and requires typing `destroy` once before its automatic Terraform steps. Set `TF_AUTO_APPROVE=true` to skip that confirmation. Creation preserves Terraform confirmation by default and supports the same environment option. See [the script guide](../../script/run_infra_destroy.md) for usage.

If creation fails before Terraform records the node group, Terraform dependencies alone cannot protect its IAM role: the untracked resource is absent from the graph. The script guard handles that case by stopping, rather than automatically deleting the AWS resource or rebuilding it. If Terraform reports a state persistence failure, retain `errored.tfstate` and reconcile it deliberately; these checks do not recover lost state automatically. Direct `terraform destroy` bypasses the script guard.

Run the offline regression tests with:

```bash
python3 -m unittest discover -s script/tests -v
```

Tests replace authentication and AWS/Terraform commands in temporary directories. Precondition tests use the actual root lifecycle checks with local EC2 response fixtures. They do not create AWS resources or replace a live plan/deployment check.

## Behavior and Limitations

`max_size` defines the capacity limit; it does not automatically scale nodes based on Pod demand. Install Cluster Autoscaler separately if needed.
Terraform manages `desired_size`. The next apply will revert changes made by manual scaling.
To keep the example simple, VPC CNI permissions are attached to the node IAM role. For production, consider a dedicated IRSA or Pod Identity role.
This module does not install the EBS CSI Driver, AWS Load Balancer Controller, or an Ingress controller. Configure persistent volumes and Ingress separately as needed.

The EKS control plane, EC2 instances, disks, and networking resources such as NAT Gateways incur charges. Before cleanup, delete load balancers and storage created by workloads, then destroy the corresponding resources through the calling Terraform configuration. Running `terraform destroy` in the root module also deletes the VPC and budget resources managed by that root module.

References: [AWS Provider EKS cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_cluster), [Managed node group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_node_group).
