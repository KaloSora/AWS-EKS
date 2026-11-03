# AWS Load Balancer Controller

This child module installs the AWS Load Balancer Controller using Helm chart
3.6.2 (Controller v3.6.2), creates a dedicated IRSA role and attaches the matching
vendored upstream IAM policy. It keeps the existing Helm resource name
`helm_release.aws_load_balancer_controller`. The previous required
`alb_controller_role_arn` input is replaced by an output: callers no longer need
to create that role themselves.

## Prerequisites

- An existing standard EKS cluster, managed nodes and Amazon VPC CNI.
- An IAM OIDC provider for the cluster issuer, including audience
  `sts.amazonaws.com`. The module looks it up and does not create or adopt it.
  In this repository `module.eks` manages that provider when
  `eks_csi_enabled = true`; configuration is not proof it exists in AWS.
  If CSI is disabled, configure a shared OIDC provider before using this module.
- Inherited AWS and Helm providers pointing to the same cluster/region. The
  Helm provider needs a working kubeconfig and authorized AWS session.
- Private-node egress to the image registry, regional STS, EC2 and ELB APIs.
  The current NAT can provide this; the S3 Gateway endpoint alone cannot.
- Control-plane access to the Controller webhook on TCP 9443. The current EKS
  managed nodes share the cluster security group; custom node/Pod security
  groups must explicitly preserve this connectivity.
- At least two suitable subnets across distinct AZs with sufficient free IPs.
  Existing public `kubernetes.io/role/elb=1` and private
  `kubernetes.io/role/internal-elb=1` tags support discovery. Backend security
  groups must permit ALB traffic and health checks on application ports.
- No existing Controller release or conflicting `alb` IngressClass managed by
  another tool. Existing resources are not automatically imported.

## Root integration example

The root calls this module from `modules/eks_ingress.tf`. Configure
`eks_ingress_chart_version` and `eks_ingress_replica_count` in `modules/dev.tfvars`;
the root passes them into this child module. The create script applies EKS,
generates kubeconfig, applies storage, then applies this Controller as a separate
stage with Terraform confirmation preserved unless `TF_AUTO_APPROVE=true`.

```hcl
module "eks_ingress" {
  source = "./eks_ingress"

  cluster_name = module.eks.cluster_name
  aws_region   = var.aws_region
  vpc_id       = module.vpc.vpc_id

  alb_controller_chart_version = var.eks_ingress_chart_version
  replica_count                = var.eks_ingress_replica_count
  acm_certificate_arn           = module.acm.certificate_arn

  tags = {
    Environment = var.aws_env
    ManagedBy   = "Terraform"
  }

  # Ensures the cluster OIDC provider and nodes are ready before lookups/install.
  depends_on = [module.eks]
}
```

Use the existing root Helm provider configured with
`eks_kubeconfig_file = "eks_kubeconfig/config"`. First create EKS and its IAM
OIDC provider, then generate kubeconfig, then review an ingress-module plan.
A Terraform dependency does not generate kubeconfig or guarantee local access.
With the root call in place, a deliberate scoped review from `modules/` is:

```bash
terraform plan -var-file=dev.tfvars -target=module.eks_ingress
```

Targeting includes dependencies and may propose other infrastructure changes;
it is not a full-root review or authorization to apply. Authentication must use
permitted sources; do not source restricted credential files for this command.
The root's certificate reference also includes `module.acm` and its hosted-zone
dependencies in scoped creation plans. Confirm DNS delegation and inspect the
plan even when the certificate has already been applied.

The module creates the `kube-system/aws-load-balancer-controller` ServiceAccount
through Helm. Its dedicated role trusts only that ServiceAccount and the cluster
issuer with `aud=sts.amazonaws.com`. IAM attachment completion precedes Helm
installation. Role/policy names use generated suffixes to avoid global collisions.
The AWS provider region must match `aws_region`.

## Helm values

Helm configuration lives in
`helm_value/aws-load-balancer-controller.yaml.tftpl`. The Helm release renders
this YAML template with `templatefile`, passing the cluster name, AWS region,
VPC ID, replica count, ServiceAccount name, generated IRSA role ARN and optional
ACM certificate ARN. Dynamic
strings use `jsonencode` to preserve YAML scalar types and escaping. Keep the
`.tftpl` file with the module when copying or packaging its Terraform source;
no generated values file is written to the repository.

## Application behavior

Select `spec.ingressClassName: alb` explicitly. The class is not the default;
legacy ingress-class annotations are disabled. The default target type is `ip`,
so VPC-routable Pod IPs can be registered behind ClusterIP Services. An application
can override supported routing settings using ALB annotations.

This module creates no application, Ingress, ALB, listener, certificate, DNS record,
PV or PVC. Creating an ALB Ingress later causes the Controller to provision AWS
resources. Public/internal scheme, listener ports, trusted client CIDRs, DNS,
application health paths and backend ports belong to that application.

### Shared ACM certificate

The optional `acm_certificate_arn` input configures the chart-managed
`IngressClassParams.spec.certificateArn` and links the existing `alb` IngressClass
to it. The root passes the issued `module.acm.certificate_arn`, so certificate
validation precedes the Controller Helm update. The certificate must be issued,
belong to the ALB account and region, and cover each application's hostname.
The module validates ARN syntax and region; it does not perform live certificate
status, account ownership or hostname checks.

This is a class-wide setting: it overrides certificate annotations on **all**
Ingresses using `ingressClassName: alb`, including existing ones. Review those
Ingresses before applying, especially ones using other domains or certificates.
Standalone callers default to `null`, which preserves per-application certificate
annotations/discovery and creates no IngressClassParams. Returning to `null` removes
the shared policy; configure application certificates before doing so.

With a shared certificate and no `listen-ports` annotation, Controller v3.6.2
defaults to HTTPS 443. An existing explicit HTTP-only annotation remains HTTP-only.
For HTTP-to-HTTPS redirection, configure the application Ingress as follows,
keeping its actual namespace, Service, port and health checks:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web
  namespace: default
  annotations:
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'
    alb.ingress.kubernetes.io/ssl-redirect: "443"
spec:
  ingressClassName: alb
  rules:
    - host: app.kalosora.live
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: web
                port:
                  number: 80
```

No TLS Secret or certificate annotation is needed in this mode. Keep the existing
scheme annotation if present; this module does not change public/internal exposure.
Point the application DNS name to the ALB separately. If Helm/GitOps owns the
Ingress, update its source values/manifests. A Helm update alone does not create
an application ALB or prove HTTPS traffic works.

Existing installations must have the v3.6.2 IngressClassParams CRD schema, including
`spec.certificateArn`. Helm upgrades do not update CRDs automatically; review any
required CRD upgrade separately before applying. Do not import or adopt an existing
IngressClassParams owned by another tool. The chart's bundled parameter object
is exempted from its own validation webhook to avoid installation dependency
cycles, so validate the rendered resource against the pinned CRD before deployment.

Two Controller replicas are requested by default, with 100m CPU / 128Mi memory
requests and a 256Mi memory limit per Pod. Replica placement and availability
still depend on node capacity; `replica_count = 1` gives up standby failover.
The chart creates its RBAC, webhook TLS Secret and `alb` IngressClass. It does
not grant cluster-wide Kubernetes Secret read access by default. The Service
mutator webhook is disabled to avoid changing new LoadBalancer Services. ALB
and NLB Gateway API feature gates are disabled; Gateway API is outside this module.

## IAM policy provenance and upgrades

`policies/iam_policy_v3.6.2.json` is an unmodified copy of:
https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v3.6.2/docs/install/iam_policy.json

The pinned policy is the upstream standard AWS-partition policy, including
read APIs and Controller write permissions for load balancers, target groups,
listeners, security groups, WAF/Shield integration and a service-linked-role
creation permission limited to Elastic Load Balancing. It contains wildcard
resources for some operations; review its scope for the account. It grants no
unrestricted `iam:*` or `iam:PassRole`. China/GovCloud partitions require a
separately reviewed policy and are not supported by this bundled policy.

The chart version input is deliberately limited to 3.6.2 to keep chart, image,
CRDs and IAM policy aligned. Upgrade them together after reviewing release notes,
Kubernetes compatibility and rendered RBAC/manifests. Helm installs chart CRDs
on initial installation but does not automatically upgrade/delete them; review
CRD changes separately before upgrades. No automatic CRD mutation is added here.

## Teardown and costs

Delete application Ingresses and other Controller-owned resources while the
Controller, its IAM permissions, EKS API and nodes still operate. Wait for AWS
load balancer/target-group/security-group cleanup; a deleted Ingress or failed
wait alone is not proof of cleanup. Then remove this module before removing EKS,
its OIDC provider, nodes and NAT. Do not remove finalizers or state to bypass
cleanup failures. Helm uninstall alone does not delete application Ingresses or
prove their AWS resources are gone; chart CRDs can remain.

The destroy script requires typing `destroy` once, then runs a read-only cleanup
gate before any deletion. It refuses remaining application Ingresses (all classes),
LoadBalancer Services and TargetGroupBindings. It discovers the TargetGroupBinding
API before querying it; discovery/list/authentication errors stop teardown. AWS
Resource Groups Tagging API auto-pagination checks load balancers and target
groups tagged `elbv2.k8s.aws/cluster=<cluster-name>` in the configured region,
even when the Controller module is absent from Terraform state. Residual resources,
malformed inventories or API errors stop teardown without uninstalling the Controller.
The script requires `tag:GetResources` plus cluster-wide list access to Ingresses,
Services and TargetGroupBindings and API discovery permissions. It does not delete
application resources, strip finalizers, retry cleanup or modify Terraform state.

After the gate passes, tracked `module.eks_ingress` resources (including partial
IAM-only applies) are destroyed before storage cleanup, nodes, EKS/OIDC and NAT.
Uninstall failures stop later teardown. An absent cluster with tracked ingress or
storage resources requires explicit recovery; the script stops. Untagged AWS
resources and residual security groups are outside the automatic inventory and
must be reviewed separately. Stop workload/GitOps controllers that can recreate
entry resources before teardown; the gate cannot prevent concurrent changes.

The Controller consumes existing node capacity. ALBs incur separate hourly/LCU,
public IPv4 and applicable traffic charges after provisioning. Budget alerts do
not impose a spending cap. No deployment, live plan, ALB health check or traffic
verification is implied by local Terraform/Helm validation.

## References

- [Controller v3.6.2 installation](https://github.com/kubernetes-sigs/aws-load-balancer-controller/blob/v3.6.2/docs/deploy/installation.md)
- [ALB Ingress configuration](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/ingress/annotations/)
- [IngressClass certificate policy](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/ingress/ingress_class/#speccertificatearn)
- [IRSA trust policies](https://docs.aws.amazon.com/eks/latest/userguide/associate-service-account-role.html)
