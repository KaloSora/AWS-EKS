# EKS CI/CD components

This module installs enabled CI/CD components from the root `eks_components`
inventory with pinned Helm chart versions. Terraform creates a namespace for
each enabled component; Helm manages the release in that namespace. Argo CD and
Jenkins are configured in `modules/dev.tfvars`.

## Jenkins

The development configuration installs the official Jenkins chart
(`jenkins/jenkins`, chart version `5.11.0`) in the `jenkins` namespace. Jenkins
uses an 8 GiB persistent volume on the EBS StorageClass passed to this module.
The generated administrator credentials are stored in the `jenkins` Kubernetes
Secret; Terraform does not set or output the password.

Jenkins is configured with the `aws-eks-app` Multibranch Pipeline job. It scans
`https://github.com/KaloSora/AWS-EKS-APP.git` for `JIRA-*` branches, excluding
no branches, and reads each matching branch's `ci/jenkins/Jenkinsfile`. The
GitHub repository must be publicly readable for this credential-free
configuration; private repositories need a Jenkins credential configured
separately. Branch indexing runs every 5 minutes. The Job DSL plugin creates
the job through JCasC, and the chart
initialization reruns on upgrades to install declared plugins. Plugin versions
and dependency resolution are pinned to avoid opportunistic latest-version
updates.

### Build agents

The chart registers the `aws-eks-app` pod template from
[`pod_templates/aws-eks-app.yaml`](pod_templates/aws-eks-app.yaml) through
JCasC. Application Jenkinsfiles select it with `inheritFrom 'aws-eks-app'`.
Terraform creates the `cicd-build` namespace and the
`jenkins-ecr-publisher` service account before Helm configures the controller
and the agent scheduling RBAC. Jenkins creates the pods when jobs run.
The agent namespace audits and warns against the restricted Pod Security
Standard because the Kaniko build container runs as UID 0.

Set the root `jenkins_ecr_role_arn` variable before publishing to ECR. The
existing role must trust the cluster's OIDC provider with audience
`sts.amazonaws.com` and subject
`system:serviceaccount:cicd-build:jenkins-ecr-publisher`, and its push
permissions should be scoped to the intended ECR repository. IRSA is injected
only into the Kaniko container. Use this job with trusted SCM branches.
The pipeline publishes from `main`; include `main` in branch discovery when
enabling release builds.

When `eks_argocd_ingress_enabled` is true, Terraform creates a
separate internet-facing HTTPS ALB Ingress for `jenkins.kalosora.live`, uses the
configured ACM certificate, restricts inbound traffic to the configured
trusted CIDRs, and publishes an ALIAS record in Route 53. TLS terminates at the
ALB and the ALB connects to Jenkins over HTTP inside the cluster. The separate
ALB has AWS hourly and data-transfer costs.

After deployment, retrieve the generated administrator username and password
using an authorized Kubernetes session:

```bash
kubectl --kubeconfig "$PWD/modules/eks_kubeconfig/config" --context dev-eks \
  -n jenkins get secret jenkins \
  -o jsonpath='{.data.jenkins-admin-user}' | base64 -d && printf '\n'

kubectl --kubeconfig "$PWD/modules/eks_kubeconfig/config" --context dev-eks \
  -n jenkins get secret jenkins \
  -o jsonpath='{.data.jenkins-admin-password}' | base64 -d && printf '\n'
```

Helm upgrades preserve Jenkins' PVC, but deleting the `jenkins` namespace also
deletes the claim; the EBS volume then follows its StorageClass reclaim policy.
Review the PVC and volume before destroying or recreating the module. This
configuration does not provide Jenkins backup or restore.
