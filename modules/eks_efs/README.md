# EKS EFS

Creates an encrypted Regional EFS file system using the AWS-managed EFS KMS key,
a dedicated security group, and one mount target in each supplied private subnet.
AZ map keys keep mount-target resource addresses stable. The caller must supply
one subnet per AZ, all in the same VPC, with VPC DNS enabled. No CSI controller,
Access Point, PVC, IAM role, backup policy or lifecycle tiering is created here.

## Root configuration

`modules/dev.tfvars` supplies the display name and throughput mode:

```hcl
eks_efs_file_system_name = "dev-eks-efs"
eks_efs_throughput_mode  = "bursting"
```

The name is the `Name` tag, not an AWS file system ID or creation token. Renaming
the tag alone does not replace the file system. `modules/eks_efs.tf` supplies the
VPC and private subnet map, and separately permits TCP 2049 only from the existing
EKS cluster security group attached to managed nodes. The module itself has no
dependency on EKS. Security group return traffic is stateful; no unrestricted
egress rule is needed on mount targets. Future custom node/Pod security groups
must be reviewed before changing the NFS rule.

`module.eks_efs.file_system_id` waits for mount targets and is passed directly
into `module.eks_storage.efs_file_system_id`. Storage installation also waits for
the cluster-specific NFS ingress rule and EKS CSI add-ons. Root output
`eks_efs_file_system_id` exposes the resulting ID for operators.

## Deployment and teardown

Use the existing EKS create process first so the local kubeconfig exists. Then
review a storage plan from `modules/`:

```bash
terraform plan -var-file=dev.tfvars -target=module.eks_storage
```

This deliberate scoped operation includes the new EFS, mount targets, NFS rule
and existing EKS/VPC dependencies; it can propose changes outside storage. Review
the actual plan before an approved apply. The existing create script targets EKS
only and does not automatically deploy EFS or the Helm release. The target is
not a substitute for reviewing the complete configuration.

Before removing a cluster, stop workloads, remove disposable PVCs and wait for
CSI cleanup while the nodes, controllers, permissions and network still work.
Remove the Helm release while the Kubernetes API remains available. Existing
targeted EKS destroy operations include dependents such as the Helm release and
cluster-specific NFS rule; inspect their actual plans. They retain this EFS
module, its mount targets and its security group, so a later cluster can reuse
the same file system. They do not automatically remove PVC data.

A full root destroy includes the file system and is permanently destructive to
its data. `reclaimPolicy` does not protect a file system deleted by Terraform.
Encryption changes can require replacement. Back up required data before any
reviewed deletion/replacement. No destroy or data migration is automated here.

## Costs and validation limits

Bursting is the root and standalone default: throughput depends on Standard
storage size and burst credits, so tiny POC file systems can be throttled under
sustained I/O. Elastic is configurable and charges for metered reads/writes.
Storage charges continue for retained data after EKS deletion. No IA/Archive
lifecycle is enabled by this module. Backups, replication, transfers and other
account settings can add charges; inspect actual account configuration.

The root currently uses `Delete` for both StorageClasses, while the standalone
storage module defaults to `Retain`. EFS dynamic provisioning deletes Access
Points on reclamation but by default retains their directories/data. It does
not delete this file system. Helm readiness does not prove NFS mount or
provisioning health; approved live PVC/Pod tests are still required.
