resource "aws_efs_file_system" "this" {
  encrypted        = true
  performance_mode = "generalPurpose"
  throughput_mode  = var.throughput_mode

  # No availability_zone_name: this is a Regional file system.
  # Keep the provider-generated creation token independent of the display name.
  tags = merge(var.tags, { Name = var.file_system_name })
}

resource "aws_security_group" "mount_targets" {
  name_prefix = "eks-efs-"
  description = "EFS mount targets; NFS ingress is managed by the caller"
  vpc_id      = var.vpc_id

  # No broad ingress or egress rules. NFS responses use stateful SG tracking.
  tags = merge(var.tags, { Name = var.file_system_name })
}

resource "aws_efs_mount_target" "this" {
  for_each = var.private_subnet_ids_by_az

  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = each.value
  security_groups = [aws_security_group.mount_targets.id]
}
