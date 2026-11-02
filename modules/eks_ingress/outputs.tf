output "alb_controller_role_arn" {
  description = "Dedicated IRSA role created for the Controller"
  value       = aws_iam_role.controller.arn
  depends_on  = [aws_iam_role_policy_attachment.controller]
}

output "alb_controller_policy_arn" {
  description = "Versioned Controller IAM policy ARN"
  value       = aws_iam_policy.controller.arn
}

output "helm_release_name" {
  description = "Controller Helm release name after installation"
  value       = helm_release.aws_load_balancer_controller.name
}

output "ingress_class_name" {
  description = "Explicit ingressClassName to select in application Ingresses"
  value       = "alb"
  depends_on  = [helm_release.aws_load_balancer_controller]
}
