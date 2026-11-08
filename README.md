# AWS-EKS

## EKS Platform Tool

This section describes the platform tools to introduce incrementally on this
standard EKS cluster. It is a roadmap, not a list of deployed services. Existing
Terraform configuration covers VPC CNI/CoreDNS/kube-proxy, the AWS Load Balancer
Controller, optional EBS/EFS CSI add-ons and StorageClasses. Configuration alone
is not evidence of a successful deployment. Argo CD is configured through `modules/eks_platform` using a pinned Helm chart.
Application repositories and automated delivery workflows are not bootstrapped.

| Layer | Tools | Purpose | Implement status |
| :--- | :--- | :--- | :---: |
| Networking and network policy | [Amazon VPC CNI](https://docs.aws.amazon.com/eks/latest/best-practices/networking.html) / [Calico](https://docs.tigera.io/calico/latest/getting-started/kubernetes/managed-public-cloud/eks/) | VPC CNI assigns VPC IP addresses to Pods. NetworkPolicy controls allowed Pod traffic. | ✅ |
| Ingress and HTTPS | [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/) + ACM | Reconciles application Ingresses into ALBs and configures routing and TLS termination with ACM certificates. | ✅ |
| Service Mesh | [Istio](https://istio.io/latest/docs/) / [Linkerd](https://linkerd.io/docs/overview/) | Manages service-to-service communication with mutual TLS (mTLS), traffic routing, retries/timeouts, authorization policies and service-level telemetry. | ❌ |
| DNS automation | [ExternalDNS](https://kubernetes-sigs.github.io/external-dns/latest/) + Route 53 | Reconciles application DNS records from selected Kubernetes resources. | ✅ |
| Application delivery | Helm / Kustomize + [Argo CD](https://argo-cd.readthedocs.io/en/stable/) | Helm packages applications; Kustomize applies environment overlays; Argo CD reconciles their desired state from Git. | ❌ |
| Metrics, dashboards and alerts | [Prometheus Operator](https://prometheus-operator.dev/docs/getting-started/introduction/) / kube-prometheus-stack, Grafana, Alertmanager; CloudWatch | Prometheus collects metrics, Grafana provides dashboards, and Alertmanager routes alerts. CloudWatch supplies AWS service telemetry and an optional managed observability path. | ❌ |
| Centralized logging | Fluent Bit + CloudWatch Logs, or [Grafana Alloy](https://grafana.com/docs/alloy/latest/collect/) + Loki | Agents collect and forward container logs; CloudWatch Logs or Loki stores and queries them; Grafana can visualize Loki logs. | ❌ |
| Distributed tracing | [OpenTelemetry Collector](https://opentelemetry.io/docs/collector/) + Tempo or AWS X-Ray | Collects instrumented application traces to investigate latency and requests across services. | ❌ |
| Workload identity and secrets | IRSA / EKS Pod Identity; [External Secrets Operator](https://external-secrets.io/latest/provider/aws-secrets-manager/) + AWS Secrets Manager; HashiCorp Vault | Workload identity grants scoped AWS access. External Secrets synchronizes external values into Kubernetes Secrets. Vault offers additional secret lifecycle and dynamic-credential capabilities. | ✅ |
| Persistent storage | [Amazon EBS CSI Driver](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html) / [Amazon EFS CSI Driver](https://docs.aws.amazon.com/eks/latest/userguide/efs-csi.html) | EBS provides block volumes, typically for single-node writers; EFS provides shared NFS storage for multiple Pods/nodes. CSI drivers integrate these services with PVC provisioning and mounts. | ✅ |
| Pod autoscaling | [Metrics Server](https://kubernetes-sigs.github.io/metrics-server/) + HPA; optional [KEDA](https://keda.sh/docs/latest/concepts/) | Metrics Server supplies resource metrics; HPA changes Pod replica counts; KEDA adds event-driven scaling. | ❌ |
| Node autoscaling | [Karpenter](https://karpenter.sh/docs/) or Cluster Autoscaler | Karpenter provisions suitable EC2 capacity for pending Pods and consolidates nodes; Cluster Autoscaler adjusts configured node groups. | ❌ |
| Policy and supply-chain security | [Kyverno](https://kyverno.io/docs/introduction/) + [Trivy](https://trivy.dev/docs/latest/guide/) | Kyverno validates or mutates Kubernetes resources and can enforce image policies. Trivy scans images and configuration for vulnerabilities, misconfiguration and exposed secrets. | ❌ |
| Backup and recovery | [Velero](https://velero.io/docs/) / [AWS Backup](https://docs.aws.amazon.com/aws-backup/latest/devguide/eks-backups.html) | Protect Kubernetes resource definitions and supported persistent data through the selected backup integrations. | ❌ |
| Infrastructure self-service | [Crossplane](https://docs.crossplane.io/latest/) | Exposes platform APIs and continuously reconciles infrastructure through providers and compositions. | ❌ |
| Internal developer portal （IDP） | [Backstage](https://backstage.io/docs/overview/what-is-backstage/) | Provides a service catalog, documentation and software templates that can connect GitOps and infrastructure self-service workflows. | ❌ |

### Suggested rollout

1. **Establish the baseline:** verify existing network, ingress/ACM and storage;
   finish Argo CD bootstrap; introduce workload identity and external secrets.
2. **Operate applications:** add metrics/alerts and one logging pipeline, then
   DNS automation, policy/scanning and backup with a successful restore drill.
3. **Expand when justified:** add Pod autoscaling, evaluate node autoscaling,
   introduce tracing, then consider Crossplane and Backstage for self-service.

### Implementation and cost boundaries

Terraform should own the EKS infrastructure and explicitly selected bootstrap
components. GitOps can own subsequent platform charts and applications. Record
ownership for Helm releases, Kubernetes objects, AWS resources and DNS records
so that two controllers do not reconcile the same resource. Before adoption,
review compatible EKS/chart/CRD versions, IAM/RBAC, resource requests, persistent
storage, upgrades, teardown and validation; no versions are pinned by this roadmap.

Open-source software does not make its infrastructure free. Prometheus/Loki/Vault
consume node capacity and storage; ALBs, Route 53, Secrets Manager, CloudWatch,
backup storage and additional EC2 nodes can incur charges. Prefer a small initial
stack with bounded retention and workload-driven scaling. AWS Budgets alerts do
not enforce a spending cap. Use each service's default/managed encryption when it
meets requirements; introduce customer-managed KMS keys only when their additional
control is needed, with key and API costs reviewed separately.

## Terraform Runbook
| Step | Command | Description |
| :--- | :--- | :--- |
| 1 | `terraform init -backend-config="dev.s3.tfbackend"` | Terraform initialization with backend S3 bucket |
| 2 | `terraform apply -target=module.budget_alert -var-file="dev.tfvars"` | Create Budget Alert |
| 3 | `terraform apply -target=module.route53 -var-file="dev.tfvars"` | Create AWS hosted zone |
| 4 | `terraform apply -target=module.acm -var-file="dev.tfvars"` | Create ACM SSL Cert for hosted zone |
| 5 | `terraform apply -target=module.vpc -var-file="dev.tfvars"` | Create AWS VPC |
| 6 | `terraform apply -target=module.vpc_endpoint -var-file="dev.tfvars"` | Create VPC S3 Gateway endpoint only. |
| 7 | `terraform apply -target=module.ec2_nat_instance -var-file="dev.tfvars"` | Create NAT resources only when `nat_instance_enable = true`. |
| 8 | `terraform apply -target=module.eks -var-file="dev.tfvars"` | Create EKS |
| 9 | `terraform apply -target=module.eks_efs -var-file="dev.tfvars"` | Create AWS EFS |
| 10 | `terraform apply -target=module.eks_storage -var-file="dev.tfvars"` | Create AWS Storage for EFS and EBS |
| 11 | `terraform apply -target=module.eks_ingress -var-file="dev.tfvars"` | Create AWS EKS Ingress |
| 12 | `terraform apply -target=module.app -var-file="dev.tfvars"` | Create application namespace |
| 13 | `terraform apply -target=module.eks_platform -var-file="dev.tfvars"` | Install enabled platform components, including Argo CD |

## Reference
[Learn AWS EKS](https://docs.aws.amazon.com/eks/latest/userguide/learn-eks.html)
