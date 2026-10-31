# VPC Endpoint Module

Creates private AWS service connectivity without a NAT Gateway. The caller supplies a VPC with DNS support and DNS hostnames enabled, private subnets keyed by Availability Zone, and their route table IDs.

## Default Services

| Service suffix | Type | Purpose |
| --- | --- | --- |
| `ssm` | Interface | Systems Manager API |
| `ssmmessages` | Interface | SSM Agent communication and Session Manager channels |
| `ec2` | Interface | EC2 APIs used by VPC CNI, nodes, and the EBS CSI driver |
| `ebs` | Interface | EBS direct APIs for snapshot block data; does not replace `ec2` for volume management |
| `elasticfilesystem` | Interface | EFS management API, including access point operations |
| `logs` | Interface | CloudWatch Logs API |
| `monitoring` | Interface | CloudWatch Metrics API |
| `ecr.api` | Interface | ECR API and image authentication |
| `ecr.dkr` | Interface | ECR container registry access |
| `sts` | Interface | Regional STS API, including IRSA credential requests |
| `eks` | Interface | EKS management API; separate from the Kubernetes API endpoint |
| `eks-auth` | Interface | EKS Pod Identity credential requests |
| `s3` | Gateway | S3 access, including ECR image layer downloads |

The root module reads the Interface service list from `vpc_endpoint_interface_services` in `modules/dev.tfvars`. The development configuration now sets this list to `[]` because a shared EC2 NAT instance provides egress; no Interface endpoints are created in that configuration. The standalone module defaults below remain available when private service connectivity is needed. S3 Gateway access is enabled separately. The standalone module default creates 12 Interface endpoints, with one ENI per endpoint in each selected AZ, and one S3 Gateway endpoint. With the current three-AZ VPC, this means 36 Interface endpoint ENIs. Interface endpoints incur per-AZ hourly and data-processing charges; remove unused services from the list to reduce cost.

`ec2messages` is not enabled by default. Current SSM Agents use `ssmmessages`; older agents may also require `ec2messages` in regions where it is supported. Add it to the service list only when needed. Additional services such as `kms`, `secretsmanager`, or `autoscaling` can be added using their service suffixes. Regional service names and AZ support are checked using the AWS provider.

## Root Integration

`modules/vpc_endpoint.tf` connects this module to the existing VPC. `module.vpc.private_route_table_ids` exposes existing route tables without replacing them. The EKS root module depends on `module.vpc_endpoint`, so EKS creation through the existing script also includes endpoint dependencies.

The essential inputs are:

```hcl
module "vpc_endpoint" {
  source = "./vpc_endpoint"

  name   = var.aws_env
  vpc_id = module.vpc.vpc_id
  private_subnets = {
    for az, subnet in module.vpc.subnets_by_az : az => {
      subnet_id      = subnet.private_subnet_id
      cidr_block     = subnet.private_cidr
      route_table_id = module.vpc.private_route_table_ids[az]
    }
  }

  interface_services = var.vpc_endpoint_interface_services
  enable_s3_gateway  = true
}
```

Each Interface endpoint has private DNS enabled. A shared security group permits inbound TCP 443 only from the supplied private subnet CIDRs. It has no outbound rules because response traffic is stateful. Client security groups must permit outbound HTTPS; custom NACLs must also allow request and return traffic. The S3 Gateway endpoint associates with all supplied private route tables. Do not manage the same endpoint associations separately.

Optional `endpoint_policies` accepts JSON policies keyed by service suffix, including `s3`. When omitted, AWS default endpoint policies apply. Endpoint connectivity does not grant IAM permissions: configure least-privilege workload roles separately. When restricting the S3 policy, preserve access to the regional ECR layer buckets and any SSM or application buckets you use.

## Validation and Deployment

From the project root:

```bash
terraform -chdir=modules init -backend-config="dev.s3.tfbackend"
terraform -chdir=modules fmt -check -recursive
terraform -chdir=modules validate
terraform -chdir=modules plan -var-file="dev.tfvars"
```

Review and approve the plan before deployment. A full root plan also includes the budget, VPC, and EKS resources. For a separate endpoint bootstrap step, use:

```bash
terraform -chdir=modules plan -var-file="dev.tfvars" -target=module.vpc_endpoint
terraform -chdir=modules apply -var-file="dev.tfvars" -target=module.vpc_endpoint
```

Targeting is intended for staged bootstrap or recovery. Follow it with a full plan to check the remaining configuration. No NAT resource is created by this module. The root configuration now uses an EC2 NAT instance. S3 Gateway routes remain in place; paid Interface endpoints can be enabled explicitly if needed.

## What Endpoints Do Not Provide

- **SSM:** An installed and running SSM Agent and an instance role with the required permissions (typically `AmazonSSMManagedInstanceCore`) are still needed. This module does not change node IAM roles or install agents.
- **EFS:** The endpoint serves EFS management APIs. File access still requires an EFS file system, mount targets, DNS resolution, and TCP 2049 between clients and mount targets.
- **EBS:** The `ec2` endpoint serves volume lifecycle operations used by the EBS CSI driver. The `ebs` endpoint serves EBS direct snapshot APIs. Neither installs the CSI driver, creates volumes, or grants its IAM permissions.
- **CloudWatch:** Endpoints provide API connectivity; agents, collectors, log groups, and IAM permissions are configured separately.
- **EKS:** Keep private Kubernetes API access enabled for node connectivity. The `eks` Interface endpoint is for AWS management APIs, not the Kubernetes API. IRSA clients must use regional STS endpoints; Pod Identity also requires its agent and associations.
- **Internet access:** Endpoints alone do not provide access to Docker Hub, GitHub, package repositories, or other external destinations; the root NAT instance provides that access. Mirror required images into private ECR before deploying them. ECR pull-through cache misses can require internet access; endpoints alone do not cover all upstream fetches.

## References

- [AWS EKS private cluster requirements](https://docs.aws.amazon.com/eks/latest/userguide/private-clusters.html)
- [Systems Manager VPC endpoints](https://docs.aws.amazon.com/systems-manager/latest/userguide/setup-create-vpc.html)
- [EFS Interface endpoints](https://docs.aws.amazon.com/efs/latest/ug/efs-vpc-endpoints.html)
- [EBS direct API endpoints](https://docs.aws.amazon.com/ebs/latest/userguide/ebs-apis-vpc-endpoints.html)
- [Terraform VPC endpoint resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint)
