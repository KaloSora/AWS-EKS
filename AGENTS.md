# AGENTS.md

## 1. Scope and Project Facts

This repository provisions standard Amazon EKS infrastructure using Terraform and the AWS provider. Work from the actual source and current task context; do not assume resources are deployed merely because configuration exists.

Current architecture:

- The Terraform root is `modules/`, using an S3 backend configured through `modules/dev.s3.tfbackend`.
- `modules/vpc` creates a VPC, three public/private subnet pairs, an Internet Gateway, and route tables.
- `modules/ec2_nat_instance` provides one shared AL2023 NAT EC2 in the first public subnet, with an Elastic IP, dedicated ENI, SSM role, and private default routes.
- `modules/eks` creates a standard EKS control plane, an EC2 managed node group, IAM resources, administrator access entries, and VPC CNI/CoreDNS/kube-proxy add-ons. EKS Auto Mode is not enabled.
- Worker nodes remain in private subnets. Public Kubernetes API access is limited by configured CIDRs; private access is enabled.
- `modules/vpc_endpoint` supports S3 Gateway and optional Interface endpoints. The development Interface service list is empty; the root configuration enables S3 Gateway access.
- `modules/budget_alert` creates a budget alert. Alerts do not enforce a spending cap or stop resources.
- `modules/eks_preflight.tf` checks requested node types before EKS creation. The standalone EKS module also validates its selection.

CI/CD, observability, additional storage controllers, workload backup, and further security hardening are future capabilities unless corresponding code is present. Do not describe Crossplane, Helm releases, `modules/k8s_cicd`, or legacy templates as implemented features without evidence.

AWS manages the EKS control plane. Do not promise direct etcd access or self-managed etcd snapshots; distinguish workload/PV backup and restore from recovery of AWS-managed control-plane state.

## 2. Workspace and Repository Discipline

- Confirm the working directory, Git status, branch/worktree, and applicable instructions before editing.
- A Codex worktree and the user's main checkout are separate directories. Modify the checkout requested by the user, and state which checkout received changes. Do not claim synchronization unless files were actually copied and verified.
- Read relevant modules, callers, scripts, tests, and documentation before changing interfaces or behavior.
- Preserve user edits and unrelated untracked files. Recheck destination files before synchronizing staged changes to another checkout.
- Keep changes scoped and incremental. Reuse local modules and existing tools; justify new dependencies.
- Do not commit, push, deploy, or delete resources unless authorized for that operation.

## 3. Terraform Implementation

- Follow the current Terraform >= 1.5.7 and AWS provider `~> 6.0` constraints unless the task requires a reviewed upgrade.
- Put configurable account, region, network, instance, and scaling settings in typed variables; pass root variables from `dev.tfvars` into child modules.
- Root `tfvars` files do not directly set child-module variables.
- Validate inputs and expose outputs needed by callers or operators. Preserve resource addresses and identities unless a change requires migration or replacement.
- Assess creation, replacement, deletion, IAM impact, route changes, and state consequences before proposing infrastructure changes.
- Keep AWS service policies, access entries, instance profiles, security groups and routing dependencies explicit where references alone are insufficient.
- Use regional AWS metadata for instance-type eligibility and architecture checks. Keep the root preflight independent of NAT creation so planning can reject invalid types before deployment.
- `free-tier-eligible` is an instance-type label, not proof of zero cost, sufficient credits, vCPU quota, account-plan access, or capacity in every AZ. Do not equate instance eligibility with a one-node limit.
- Preserve the standard managed-node-group architecture unless Auto Mode or another compute model is explicitly requested.
- Do not use `ignore_changes`, broad exception handling, or automatic retries merely to hide unexpected drift or failed provisioning.

### NAT and Networking

- Keep NAT ENI source/destination checks disabled. With `aws_instance.primary_network_interface`, do not also set the conflicting instance-level `source_dest_check`; manage it on the ENI.
- Preserve the public-subnet IGW route, EIP association, private default routes, IP forwarding, and reboot-persistent NAT rules.
- Keep the ENI/EIP stable where practical when replacing the NAT instance. Explain interruption risks when AMI or user-data changes force replacement.
- An EC2 instance in `running` state does not prove cloud-init/NAT readiness. Check the ready marker and forwarding rules, then verify traffic from a private node or Pod when live checks are authorized.
- A single NAT is a single point of failure; traffic from other AZs may incur cross-AZ charges. Do not silently change it to one instance or NAT Gateway per AZ.
- Interface endpoints have per-AZ hourly and data-processing charges. Do not enable a large default service set without explaining cost impact. S3 Gateway access is configured separately.
- EFS API endpoints do not replace mount targets/NFS rules. EBS direct API endpoints do not replace the EC2 API used for volume operations. Endpoint connectivity does not grant IAM permissions or install CSI/SSM/observability components.

## 4. EKS Lifecycle and State Integrity

Normal dependency order creates node IAM permissions before the managed node group and removes them after the group is deleted. The node group must also be removed before deleting the control plane.

Creation failures and state persistence failures can leave an AWS node group absent from Terraform state. Terraform's dependency graph cannot protect an untracked resource. Apply these rules:

- Preserve the AWS-versus-state comparison in `script/eks_lifecycle.sh` before create/destroy operations.
- Stop on untracked node groups, state-read failures, or AWS authentication/authorization/network errors. Treat only `ResourceNotFoundException` from cluster lookup as an absent cluster.
- Before destructive recovery, verify AWS account, region, backend, workspace, actual resources, and current state.
- Destroy tracked managed nodes first, wait for AWS to confirm node-group deletion, and recheck the AWS list before deleting cluster/IAM resources. Remove NAT last.
- A waiter timeout or `Ctrl+C` stops local waiting; it does not cancel AWS deletion. Do not continue deleting dependencies after a failed waiter.
- Do not force-delete ASGs, restore IAM roles, import resources, or change ASG capacity automatically to bypass a mismatch. Diagnose and obtain authorization for the concrete recovery action.
- Preserve `errored.tfstate` and other recovery artifacts after persistence failures. Do not modify or delete state as a workaround for configuration errors.
- Do not automatically run `state rm`, `state push`, `force-unlock`, import, or state migration. State-changing recovery requires a reviewed plan and explicit authorization.
- Do not rerun a full apply as a cleanup shortcut: configuration can recreate resources the user intended to remove.

Use targeted Terraform operations only for deliberate bootstrap, scoped teardown, or recovery. Explain dependency/coverage limitations and inspect the actual plan. The create script targets EKS and dependencies; budget and VPC endpoint modules are separate targets. The destroy script retains VPC, IGW, subnets, budget, and S3 Gateway resources.

## 5. Shell Scripts

Relevant entry points:

- `script/run_infra_create.sh`
- `script/run_infra_destroy.sh`
- `script/run_aws_auth.sh`
- `script/eks_lifecycle.sh`

Maintain the existing script style: Bash strict mode, a usage/runbook header, script-relative paths, pre-checks, clear log sections, numbered steps, propagated exit statuses, and a final state/completion summary.

- Keep paths quoted and support execution from other working directories, including paths containing spaces.
- `TF_AUTO_APPROVE` defaults to `false` and accepts only `true` or `false`.
- Creation preserves Terraform confirmation by default. Destruction requires typing `destroy` once before its automatic steps; EOF or another answer cancels.
- Do not treat a shell flag or an existing `-auto-approve` as authorization for the agent to execute a deployment or teardown.
- Propagate command failures even when helper functions are called inside conditionals. Do not print success after a failed command.
- Keep AWS lifecycle checks centralized in the helper and preserve bounded deletion waiters.
- Do not introduce account-wide destructive fallbacks, hidden force flags, or retries that mask errors.
- Print useful access instructions and non-sensitive outputs; do not display authentication material.

## 6. Credentials, IAM, and Sensitive Artifacts

Preserve these credential restrictions:

- Never read, display, copy, or execute `~/.aws/credentials`.
- Never execute `source ~/aws_env.sh` or an equivalent command that loads this file.
- Do not bypass these restrictions by reading/loading the files through another command or script. Inspect the authentication call chain before executing entry scripts; do not run a script that indirectly performs a prohibited load.
- Do not print environment variables or credential values when troubleshooting.
- Never hardcode or commit cloud credentials, tokens, passwords, private keys, or sensitive generated artifacts.
- Use approved environment credentials, secret-management mechanisms, or explicitly authorized sources. If credentials are unavailable, report the limitation without retrieving restricted files.

Use least-privilege IAM. Scope `iam:PassRole` to intended roles/services and policy attachment permissions to intended policies where practical. Do not suggest unrestricted `iam:*` on `*` as the default fix for an AccessDenied error. Distinguish the Terraform execution role, EKS administrator identity, node role, and NAT instance role.

Never commit Terraform state (including `errored.tfstate`), sensitive plans, credential JSON, private keys, or logs containing secrets. Inspect `.gitignore`, staged files and diffs before committing; do not assume current ignore rules cover every artifact. State and plan inspection should extract only fields needed for diagnosis rather than dumping full contents.

Do not widen API CIDRs or expose SSH, NodePort, or other services merely to make deployment work. Public EKS CIDRs control client access to Kubernetes; they do not provide worker-node egress.

## 7. Authorization and Operational Changes

Routine local code/documentation edits and non-destructive validation may proceed within the user's request. Inspect the implementation and explain the approach and material impacts for non-trivial work. Clarify when a proposed change exceeds the requested scope.

Explicit user approval is required before executing operations that change remote infrastructure, Terraform state, Kubernetes resources, or persistent application data, including:

- Terraform apply/destroy, deployment scripts, and state-changing commands.
- AWS CLI/API resource creation, updates, deletion, ASG changes, and IAM changes.
- Kubernetes apply/delete, Helm installation/upgrade/uninstallation, and storage or recovery operations.

Before requesting approval, complete applicable read-only checks and prepare the concrete operation for review. Present its scope, the plan/diff when available, expected replacements/deletions, data or downtime risks, and uncompleted checks. Approval applies to that reviewed operation; obtain new approval if the scope changes materially.

Successful validation, a previous deployment, shell confirmation settings, or the existence of a destroy script does not authorize a new external operation. Do not run live create/destroy scripts to test their syntax or behavior; use offline mocks.

Read-only AWS/cluster diagnostics require available, permitted authentication. Prefer resource-specific queries and avoid exposing sensitive state, requests, responses, or debug logs.

## 8. Validation

Run checks appropriate to the change. Use actual results, not assumptions.

Terraform changes:

```bash
terraform -chdir=modules fmt -check -recursive
terraform -chdir=modules validate
```

Provider initialization is required for validation. Backend-free validation can use an isolated copy containing the required `.tf` and `.tftpl` assets, with `terraform init -backend=false`. Do not confuse successful validation with a successful live plan or deployment. Report pre-existing formatting failures separately rather than broadening unrelated edits.

Shell and lifecycle changes:

```bash
bash -n script/run_infra_create.sh
bash -n script/run_infra_destroy.sh
bash -n script/eks_lifecycle.sh
python3 -m unittest discover -s script/tests -v
```

Tests must replace real authentication and AWS commands. Preserve coverage for orphaned node groups, API/state failures, failed creation, deletion wait failures, correct teardown order, confirmation/cancellation, and auto-approval settings. Preflight tests use local fixtures and do not prove live account eligibility or capacity.

For meaningful infrastructure changes, review a live Terraform plan when permitted authentication is available; otherwise explain why it was not run. Apply/destroy remains subject to approval. For document-only changes, check local links, examples, paths and consistency with source; do not run cloud operations unnecessarily.

If Helm/Kubernetes features are introduced, validate their versions, rendered manifests, RBAC, security, storage behavior and relevant tests. Do not claim backup/recovery works without a restore validation appropriate to its scope.

## 9. Documentation and Reporting

- Keep `README.md`, module READMEs and script guidance consistent with implemented behavior. Use English for repository documentation unless requested otherwise.
- Separate implemented components from roadmap items and distinguish root defaults from standalone module defaults.
- Document prerequisites, configuration, dependencies, deployment scope, costs, teardown behavior and recovery limitations where relevant.
- Do not claim checks passed unless they ran successfully. Distinguish syntax/configuration checks, mocked tests, live plans and live verification.
- Finish with a concise account of what changed, where, validation results, material operational impact, and any remaining action or limitation. For local-only changes, state that no AWS resources or state were modified when relevant.

Follow higher-priority instructions and explicit user requirements. Preserve user-approved scope and credential/operational boundaries; do not silently reinterpret an instruction in a way that exposes secrets, loses data, or changes infrastructure without authorization.
