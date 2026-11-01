# CSI controllers remain managed by the EKS add-ons in ../eks/eks_csi.tf.
# This release owns only the two cluster-scoped StorageClass objects.
resource "helm_release" "storage_classes" {
  name      = "eks-storage-classes"
  namespace = "kube-system"
  chart     = "${path.module}/charts/storage-classes"
  version   = "0.1.0"

  atomic  = true
  wait    = true
  timeout = 300

  values = [yamlencode({
    ebs = {
      name          = var.ebs_storage_class_name
      reclaimPolicy = var.reclaim_policy
    }
    efs = {
      name          = var.efs_storage_class_name
      fileSystemId  = var.efs_file_system_id
      reclaimPolicy = var.reclaim_policy
    }
  })]

  lifecycle {
    precondition {
      condition     = var.ebs_storage_class_name != var.efs_storage_class_name
      error_message = "EBS and EFS StorageClass names must be different."
    }
  }
}
