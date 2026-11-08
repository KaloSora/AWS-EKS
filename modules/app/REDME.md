# Kubernetes application environments

This module creates the namespaces used to simulate application promotion:

- `dev`
- `uat`
- `preprod`
- `prod`

Every namespace enforces, audits, and warns against the Kubernetes Pod Security Standards `restricted` profile. 
The policy version is pinned to the cluster's Kubernetes major and minor version.

The module intentionally creates no workloads, RBAC, quotas, limit ranges, or network policies. 
Application lifecycle remains the responsibility of the GitOps delivery workflow.

The `namespace_names` output exposes the environment names for callers.

The create script applies this module after storage and ingress setup. The destroy
script removes tracked namespaces after disposable PVC/PV cleanup and before
StorageClasses and EKS. Deleting a namespace deletes all resources inside it,
including workloads and PVCs created outside Terraform; review backups and other
storage classes before confirming teardown. No backup is created by the scripts.
