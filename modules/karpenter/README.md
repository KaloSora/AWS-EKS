# Karpenter

Karpenter is the node autoscaler for this standard Amazon EKS cluster. It
launches EC2 worker nodes when Pods cannot fit on existing nodes and reclaims
Karpenter-managed nodes when their capacity can be removed or consolidated.
The EKS managed node group supplies baseline capacity and hosts the Karpenter
controller. Kubernetes schedules Pods onto available nodes, and Karpenter
provisions additional capacity for the scheduler to use. [Amazon EKS autoscaling](https://docs.aws.amazon.com/eks/latest/userguide/autoscaling.html)

## How node scaling works

1. Karpenter watches unschedulable Pods and evaluates their resource requests
   and scheduling constraints, such as node selectors and availability zones.
2. A `NodePool` defines the allowed instance types, architecture, capacity type,
   and aggregate capacity limit. Its `EC2NodeClass` defines how to launch those
   instances, including the AMI, subnets, security group, and node IAM role.
3. When a compatible instance can fit the workload, Karpenter creates a
   `NodeClaim` and asks EC2 to launch it. The NodeClaim tracks launch,
   registration with EKS, and initialization. The Kubernetes scheduler can
   place Pods on the new node as it becomes available.
4. When capacity can be reclaimed, Karpenter evaluates where the affected Pods
   can run, drains the node, and terminates its EC2 instance. Pod disruption
   budgets and volume detachment can affect how long this takes.

[NodePools](https://karpenter.sh/v1.15/concepts/nodepools/) ·
[EC2NodeClasses](https://karpenter.sh/v1.15/concepts/nodeclasses/) ·
[NodeClaims](https://karpenter.sh/v1.15/concepts/nodeclaims/) ·
[Node disruption](https://karpenter.sh/v1.15/concepts/disruption/)

## Configuration in this project

The [Terraform root](../karpenter.tf) passes `eks_components.karpenter` from
[dev.tfvars](../dev.tfvars) to this module. Terraform installs the pinned
controller chart and its CRDs, and creates the controller IRSA role, EC2 node
role, and EKS access entry. IRSA uses the cluster IAM OIDC provider created when
`eks_csi_enabled` is enabled. The existing managed node group must have capacity
for the controller, and private nodes need access to the required AWS APIs and
image registries.

| Setting | Development configuration |
| --- | --- |
| `enabled` | Installs the controller in the `karpenter` namespace. |
| `config.provisioning_enabled` | `"true"` installs the `general` NodePool and its `default` EC2NodeClass through a separate Helm release. |
| `config.ami_alias` | Pins an EKS-optimized AL2023 image release. Choose a release compatible with the cluster Kubernetes version. |
| `eks_node_instance_types` | Allows only `t3.small` in the current configuration. The pool uses amd64 On-Demand instances in private subnets with no public IP. |
| `config.node_pool_cpu_limit` | `"2"` limits the pool to 2 vCPUs independently of the managed node group. The limit is eventually consistent and EC2 usage remains subject to account quotas and billing. |

## Deployment and verification

The [create script](../../script/run_infra_create.sh) applies
`module.karpenter` after EKS and before `module.eks_cicd`. With an authorized
kubeconfig, check the controller and provisioning resources after deployment.

```bash
kubectl -n karpenter get deployment karpenter
kubectl get ec2nodeclasses,nodepools,nodeclaims
kubectl get nodes -l karpenter.sh/nodepool=general
```

A ready NodePool can have zero NodeClaims when the existing nodes can fit
the workload. For a Pending Pod, check its scheduling events and the readiness
of the NodePool and EC2NodeClass. If a NodeClaim exists, inspect its conditions
with `kubectl describe nodeclaim <name>` to locate the blocked lifecycle step.

## Teardown

The [destroy script](../../script/run_infra_destroy.sh) removes Karpenter before
the managed node group and EKS control plane. The provisioning release runs a
[pre-delete cleanup job](charts/karpenter-provisioning/templates/cleanup-job.yaml)
that deletes the managed NodePool, waits for its NodeClaims to disappear, and
then removes the EC2NodeClass. Keep the controller, its AWS permissions, and
the managed node group available until the job completes. A cleanup failure
stops the teardown so the controller can finish reclaiming the nodes.
