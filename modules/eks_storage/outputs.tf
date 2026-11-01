output "storage_class_names" {
  description = "StorageClass names to reference in PVC storageClassName"
  value = {
    ebs = var.ebs_storage_class_name
    efs = var.efs_storage_class_name
  }
  depends_on = [helm_release.storage_classes]
}
