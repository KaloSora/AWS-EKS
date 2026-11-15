locals {
  jenkins_ingress_enabled = var.public_ingress != null && contains(local.enabled_component_names, "jenkins")
  jenkins_domain          = try(nonsensitive(var.components["jenkins"].config["jenkins_url"]), "")

  # Match the Jenkins chart fullname helper.
  jenkins_release_name = try(nonsensitive(var.components["jenkins"].release_name), "")
  jenkins_fullname     = trimsuffix(substr(strcontains(local.jenkins_release_name, "jenkins") ? local.jenkins_release_name : "${local.jenkins_release_name}-jenkins", 0, 63), "-")
}

resource "kubernetes_ingress_v1" "jenkins" {
  count = local.jenkins_ingress_enabled ? 1 : 0

  wait_for_load_balancer = true

  metadata {
    name      = "jenkins"
    namespace = helm_release.component["jenkins"].namespace

    annotations = {
      "alb.ingress.kubernetes.io/scheme"               = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"          = "ip"
      "alb.ingress.kubernetes.io/load-balancer-name"   = "jenkins-${substr(sha256("${var.public_ingress.alb_name}-jenkins"), 0, 12)}"
      "alb.ingress.kubernetes.io/listen-ports"         = jsonencode([{ HTTPS = 443 }])
      "alb.ingress.kubernetes.io/certificate-arn"      = var.public_ingress.certificate_arn
      "alb.ingress.kubernetes.io/inbound-cidrs"        = join(",", var.public_ingress.inbound_cidrs)
      "alb.ingress.kubernetes.io/backend-protocol"     = "HTTP"
      "alb.ingress.kubernetes.io/healthcheck-protocol" = "HTTP"
      "alb.ingress.kubernetes.io/healthcheck-path"     = "/login"
      "alb.ingress.kubernetes.io/success-codes"        = "200-399"
    }
  }

  spec {
    ingress_class_name = var.public_ingress.ingress_class

    rule {
      host = local.jenkins_domain

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = local.jenkins_fullname

              port {
                number = 8080
              }
            }
          }
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition     = endswith(local.jenkins_domain, ".${var.public_ingress.hosted_zone_name}")
      error_message = "Jenkins' hostname must be a subdomain of the configured Route 53 hosted zone."
    }
  }
}

data "aws_lb" "jenkins" {
  count = local.jenkins_ingress_enabled ? 1 : 0

  name = kubernetes_ingress_v1.jenkins[count.index].metadata[0].annotations["alb.ingress.kubernetes.io/load-balancer-name"]
}

resource "aws_route53_record" "jenkins" {
  count = local.jenkins_ingress_enabled ? 1 : 0

  zone_id = var.public_ingress.hosted_zone_id
  name    = local.jenkins_domain
  type    = "A"

  alias {
    name                   = data.aws_lb.jenkins[count.index].dns_name
    zone_id                = data.aws_lb.jenkins[count.index].zone_id
    evaluate_target_health = true
  }

  lifecycle {
    precondition {
      condition = (
        data.aws_lb.jenkins[count.index].load_balancer_type == "application" &&
        !data.aws_lb.jenkins[count.index].internal &&
        data.aws_lb.jenkins[count.index].dns_name == kubernetes_ingress_v1.jenkins[count.index].status[0].load_balancer[0].ingress[0].hostname
      )
      error_message = "The ALB lookup must match the public application load balancer reported by the Jenkins Ingress."
    }
  }
}
