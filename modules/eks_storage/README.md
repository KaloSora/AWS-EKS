# EKS StorageClasses

This child module installs the local `storage-classes` Helm chart (version 0.1.0)
as release `eks-storage-classes` in `kube-system`. The release owns exactly two
cluster-scoped resources, with no namespace, workload, RBAC, CSI controller or AWS
infrastructure creation:

| StorageClass | Provisioner | Configuration |
| --- | --- | --- |
| `ebs-sc` | `ebs.csi.aws.com` | Encrypted gp3, ext4, expansion enabled, WaitForFirstConsumer |
| `efs-sc` | `efs.csi.aws.com` | Dynamic access points in an existing EFS file system, TLS mount, Immediate binding |

Both classes default to `Retain` and neither is marked as the default class.
Existing default StorageClasses are unchanged. Select a class explicitly with
`spec.storageClassName` in a PVC; EBS typically uses ReadWriteOnce and EFS can use
ReadWriteMany. StorageClass creation and Helm readiness do not verify that a PVC
can provision, attach, mount, or retain its data.

## Prerequisites and root integration

- A reachable EKS cluster, working kubeconfig and valid authorized AWS session.
- The existing EBS/EFS EKS CSI add-ons and their IRSA permissions must be active
  (`eks_csi_enabled = true`). Do not reinstall those controllers using Helm.
- An existing EFS file system, mount targets in the required AZs, working DNS,
  and security groups permitting TCP 2049 from the nodes. An EFS API endpoint
  does not provide NFS connectivity. The EFS driver creates access points, not
  file systems or mount targets.
- Cluster authorization to manage StorageClasses and Helm's release records
  in `kube-system`. This chart creates no IAM or Kubernetes RBAC permissions.
- Class names and the Helm release name must be unused; this module does not
  automatically adopt resources managed by another tool.

The root Helm provider is already configured in `modules/provider.tf`. This
module receives that provider; it does not need an `eks_kubeconfig_file` input.
The root calls this module from `modules/eks_storage.tf`, passing
`module.eks_efs.file_system_id` automatically. Configure the EFS display name
with `eks_efs_file_system_name` in `modules/dev.tfvars`; no manual EFS ID input
is required at the root. The root uses `reclaim_policy = "Delete"` for POC,
while the standalone module default remains `Retain`.

The create script generates the kubeconfig after the EKS apply, then runs the
storage apply as a separate stage. To review storage separately from `modules/`:

```bash
terraform plan -var-file=dev.tfvars -target=module.eks_storage
```

The target includes EFS, mount targets, cluster-specific NFS ingress and EKS/VPC
dependencies. It can plan changes outside the Helm release and is not a complete
review of all root resources. The script retains Terraform confirmation for
both applies by default. See [EFS](../eks_efs/README.md) for lifecycle,
networking and retained-data costs.
Do not include initial Helm installation in the first EKS apply: its kubeconfig
is generated only after that apply completes.

## Lifecycle and costs

The release creates no PVs or PVCs. Workload claims can provision billable EBS
volumes; the separately created EFS file system also incurs storage and other
applicable charges. `Retain` keeps backing storage after PVC deletion and requires
manual PV/storage cleanup; costs can continue. EFS Access Point deletion and
directory/data cleanup are distinct operations. Choosing `Delete` changes the
cleanup behavior and must be reviewed before provisioning claims.

Provisioner, parameters and binding mode cannot generally be changed in place.
For incompatible changes, create a differently named class and plan workload/data
migration. Helm uninstall removes the classes but is not a data cleanup procedure.
The infrastructure destroy script first cleans up PVs/PVCs using `ebs-sc` and
`efs-sc` in all namespaces, then removes the tracked Helm release, then destroys
EFS and all its data before removing nodes and the control plane. Stop workload
controllers and Pods first. Cleanup refuses in-use volumes, non-Delete PVs,
wrong CSI drivers/Helm owners and EFS IDs that do not match Terraform state. It
uses normal bounded deletion, rechecks for recreated volumes and never strips
finalizers or automatically changes reclaim policies. Other classes are excluded.
The script requires cluster-wide read permissions and deletion permissions for
selected PVs/PVCs; API failures/timeouts stop teardown. For custom class names,
review `script/cleanup_eks_storage.py`, which matches the root defaults. EFS
module deletion is independent of the PVC reclaim policy and permanently deletes
all file system data. Review actual plans before teardown.
Actual provisioning, access permissions, expansion and retain behavior require
live disposable PVC/Pod checks after an approved deployment; no such checks have
been performed.

## Offline checks

```bash
helm lint --strict modules/eks_storage/charts/storage-classes \
  --set-string efs.fileSystemId=fs-0123456789abcdef0
helm template eks-storage-classes modules/eks_storage/charts/storage-classes \
  --namespace kube-system --set-string efs.fileSystemId=fs-0123456789abcdef0
```

The ID above is a local rendering fixture, not a deployed file system.
