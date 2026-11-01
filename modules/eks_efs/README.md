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

The create script applies EKS, generates the local kubeconfig, then applies the
storage target with its EFS dependencies. For a separate read-only review from
`modules/`, use:

```bash
terraform plan -var-file=dev.tfvars -target=module.eks_storage
```

This deliberate scoped operation includes the new EFS, mount targets, NFS rule
and existing EKS/VPC dependencies; it can propose changes outside storage. Review
the actual plan before an approved apply. The create script preserves Terraform
confirmation for both applies by default. The target is not a substitute for
reviewing the complete configuration.

The destroy script now treats POC data as disposable. It first cleans up PVs
and PVCs using `ebs-sc`/`efs-sc` while CSI controllers are running, then uninstalls
the Helm release, then destroys `module.eks_efs` before deleting nodes/control
plane and NAT. **This permanently deletes the entire EFS file system and all
its data**, including directories left by previously deleted Access Points.
Stop workload controllers and Pods before running the script. A volume still in
use, non-Delete PV, API error or deletion timeout stops cleanup. No finalizers
are stripped and no reclaim policy is automatically changed. Residual Access
Points or replication dependencies can block the EFS destroy; failure stops
node/control-plane teardown and requires diagnosis, without forced recovery.

The module itself has no cluster dependency. A manual targeted destroy of EKS
alone can therefore retain EFS, but the updated destroy script explicitly
includes EFS. A full root destroy also includes it. `reclaimPolicy` does not
protect a file system deleted by Terraform. Encryption changes can require
replacement. Back up required data separately before approved deletion or
replacement; this workflow creates no backup and does not migrate data.

## Costs and validation limits

Bursting is the root and standalone default: throughput depends on Standard
storage size and burst credits, so tiny POC file systems can be throttled under
sustained I/O. Elastic is configurable and charges for metered reads/writes.
Storage charges continue if EFS is retained through a separate manual teardown. No IA/Archive
lifecycle is enabled by this module. Backups, replication, transfers and other
account settings can add charges; inspect actual account configuration.

The root currently uses `Delete` for both StorageClasses, while the standalone
storage module defaults to `Retain`. EFS dynamic provisioning deletes Access
Points on reclamation but by default retains their directories/data. It does
not delete this file system. Helm readiness does not prove NFS mount or
provisioning health; approved live PVC/Pod tests are still required.
