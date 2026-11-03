# ACM public certificate

Creates one non-exportable ACM public certificate for the apex of an existing
Route 53 public hosted zone, optional additional names, DNS validation CNAMEs,
and a validation waiter. The provider region must match the intended ALB region.
No private key, application Ingress, ALB listener or application DNS alias is created.

The root `module.acm` uses `module.route53.zone_id`. The development configuration
requests `kalosora.live` and `*.kalosora.live`; the wildcard covers first-level
subdomains, not nested names such as `a.b.kalosora.live`. Standalone callers
default to the zone apex only. Additional names must belong to the supplied zone.
Apex/wildcard validation CNAMEs are deduplicated. Names delegated to another DNS
zone need validation records there and are outside this single-zone module.

```hcl
module "acm" {
  source                    = "./acm"
  hosted_zone_id            = module.route53.zone_id
  domain_name               = "example.com"
  subject_alternative_names = ["*.example.com"]
  tags                      = { ManagedBy = "Terraform" }
}
```

The explicit domain input must match the hosted zone apex. Supplying it separately
keeps record keys known during planning even when the zone is being created.

Before requesting validation, delegate the domain at its registrar to this
hosted zone's name servers. Creating the zone alone does not delegate DNS.
Restrictive CAA records must also permit Amazon certificate issuance. Validation
waits up to 45 minutes and fails if public DNS cannot validate the certificate.
Existing validation records managed elsewhere are not silently overwritten;
review their ownership before applying. Execution credentials need ACM certificate
management and Route 53 zone lookup, record management and change-status permissions.

From the Terraform root, inspect a deliberately scoped plan before applying:

```bash
terraform plan -target=module.acm -var-file=dev.tfvars
```

Targeting includes dependencies such as the hosted zone and omits unrelated root
changes; inspect the plan for any zone creation/replacement. Deployment requires
separate approval. The current create script does not target this module.

The root passes the issued ARN to `module.eks_ingress`, which configures a shared
certificate policy for Ingresses using class `alb`. Apply that reviewed Controller
update separately; the ACM apply alone does not configure the class. Configure
application listener ports and DNS separately; see [the ingress module](../eks_ingress/README.md#shared-acm-certificate).
For other IngressClasses without a shared certificate policy, use
`terraform output -raw acm_certificate_arn` to set the application's
`alb.ingress.kubernetes.io/certificate-arn` annotation. The output waits for issuance.

Non-exportable ACM public certificates used with ALB have no additional certificate
charge; Route 53 and ALB have separate charges. Retain validation CNAMEs for managed
renewal while the certificate is in use. Domain/SAN changes can replace the
certificate; `create_before_destroy` requests the replacement first, but the class
policy or application annotations must be updated to the new ARN before the old
certificate can be deleted. The root orders the Helm policy update before old
certificate destruction, but Controller reconciliation with ALB is asynchronous.
Verify listener associations; a successful Helm update does not prove the old ARN
is detached. This module cannot coordinate an externally managed Ingress update.
Remove listener associations before destroying the certificate. The scoped EKS
destroy script does not remove this module, its records or the hosted zone.

References: [ACM resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate),
[DNS validation](https://docs.aws.amazon.com/acm/latest/userguide/dns-validation.html),
[ACM pricing](https://aws.amazon.com/certificate-manager/pricing/).
