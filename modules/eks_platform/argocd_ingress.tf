locals {
  argocd_ingress_enabled = var.argocd_ingress != null && contains(local.enabled_component_names, "argocd")
  argocd_domain          = try(nonsensitive(var.components["argocd"].config["argocd_url"]), "")

  # Match the pinned chart's fullname and server fullname helpers.
  argocd_release_name = try(nonsensitive(var.components["argocd"].release_name), "")
  argocd_fullname     = trimsuffix(substr(strcontains(local.argocd_release_name, "argocd") ? local.argocd_release_name : "${local.argocd_release_name}-argocd", 0, 63), "-")
  argocd_server_name  = trimsuffix(substr("${local.argocd_fullname}-server", 0, 63), "-")
}

resource "kubernetes_ingress_v1" "argocd" {
  count = local.argocd_ingress_enabled ? 1 : 0

  wait_for_load_balancer = true

  # Depends on the Argo CD Helm release to create the argocd namespace and service.
  metadata {
    name      = "argocd"
    namespace = helm_release.component["argocd"].namespace

    annotations = {
      "alb.ingress.kubernetes.io/scheme"               = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"          = "ip"
      "alb.ingress.kubernetes.io/load-balancer-name"   = var.argocd_ingress.alb_name
      "alb.ingress.kubernetes.io/listen-ports"         = jsonencode([{ HTTPS = 443 }])
      "alb.ingress.kubernetes.io/certificate-arn"      = var.argocd_ingress.certificate_arn
      "alb.ingress.kubernetes.io/inbound-cidrs"        = join(",", var.argocd_ingress.inbound_cidrs)
      "alb.ingress.kubernetes.io/backend-protocol"     = "HTTPS"
      "alb.ingress.kubernetes.io/healthcheck-protocol" = "HTTPS"
      "alb.ingress.kubernetes.io/healthcheck-path"     = "/healthz"
    }
  }

  spec {
    ingress_class_name = var.argocd_ingress.ingress_class

    rule {
      host = local.argocd_domain

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = local.argocd_server_name

              port {
                name = "https"
              }
            }
          }
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition     = endswith(local.argocd_domain, ".${var.argocd_ingress.hosted_zone_name}")
      error_message = "Argo CD's hostname must be a subdomain of the configured Route 53 hosted zone."
    }
  }
}

data "aws_lb" "argocd" {
  count = local.argocd_ingress_enabled ? 1 : 0

  # Read the ALB only after the Ingress publishes its load balancer status.
  name = kubernetes_ingress_v1.argocd[count.index].metadata[0].annotations["alb.ingress.kubernetes.io/load-balancer-name"]
}

resource "aws_route53_record" "argocd" {
  count = local.argocd_ingress_enabled ? 1 : 0

  zone_id = var.argocd_ingress.hosted_zone_id
  name    = local.argocd_domain
  type    = "A"

  alias {
    name                   = data.aws_lb.argocd[count.index].dns_name
    zone_id                = data.aws_lb.argocd[count.index].zone_id
    evaluate_target_health = true
  }

  lifecycle {
    precondition {
      condition = (
        data.aws_lb.argocd[count.index].load_balancer_type == "application" &&
        !data.aws_lb.argocd[count.index].internal &&
        data.aws_lb.argocd[count.index].dns_name == kubernetes_ingress_v1.argocd[count.index].status[0].load_balancer[0].ingress[0].hostname
      )
      error_message = "The ALB lookup must match the public application load balancer reported by the Argo CD Ingress."
    }
  }
}
