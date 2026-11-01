output "file_system_id" {
  description = "EFS ID, available to callers after all mount targets are created"
  value       = aws_efs_file_system.this.id
  depends_on  = [aws_efs_mount_target.this]
}

output "file_system_arn" {
  description = "EFS file system ARN"
  value       = aws_efs_file_system.this.arn
}

output "mount_target_security_group_id" {
  description = "Security group to which the caller adds narrowly scoped NFS ingress"
  value       = aws_security_group.mount_targets.id
}

output "mount_target_ids" {
  description = "Mount target IDs keyed by AZ"
  value       = { for az, target in aws_efs_mount_target.this : az => target.id }
}
