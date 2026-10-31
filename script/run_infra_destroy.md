# Infrastructure Entry Scripts

The create and destroy scripts follow the layout of the reference [Tencent Cloud scripts](https://github.com/KaloSora/tencentcloud-k8s/tree/main/modules/script): usage/runbook comments, project paths, common functions, pre-checks, numbered operations, final state and completion summaries. AWS-specific lifecycle checks remain in `eks_lifecycle.sh`.

## Create

From the repository root:

```bash
./script/run_infra_create.sh
```

The script checks Terraform, AWS CLI, jq and required local files before running authentication. It initializes the configured S3 backend, validates Terraform, reads the cluster name/region, and verifies that existing AWS node groups are tracked in the current state. It then applies `module.eks` and its dependencies, displays Terraform state/outputs and prints kubectl setup commands. It does not add the budget or other unrelated modules as explicit targets.

Terraform's normal apply confirmation is preserved. For automation:

```bash
TF_AUTO_APPROVE=true ./script/run_infra_create.sh
```

## Destroy

```bash
./script/run_infra_destroy.sh
```

After initialization, validation and the AWS/state check, the script displays its targets and requires the exact word `destroy`. Any other response or EOF cancels without running destroy commands. To skip the confirmation:

```bash
TF_AUTO_APPROVE=true ./script/run_infra_destroy.sh
```

After this confirmation, individual Terraform destroy steps use `-auto-approve`:

1. Destroy `module.eks.aws_eks_node_group.this` and its dependents.
2. Wait for AWS to confirm all previously listed node groups have been removed, and query the list again.
3. Destroy the remaining `module.eks` resources, including the control plane and IAM roles.
4. Destroy `module.ec2_nat_instance`, including EC2, EIP, ENI, IAM resources and private default routes.

The displayed Terraform destroy steps are numbered 1/3 through 3/3; the AWS waiter runs between steps 1 and 2. Failures stop subsequent steps. No automatic cleanup of untracked AWS resources or automatic state repair is performed.

VPC, Internet Gateway, subnets, budget and S3 Gateway endpoint are not explicit destroy targets. Nonempty final state is expected when this infrastructure is retained. Clean up workload-created load balancers and review persistent data before running the script. Inspect a destroy plan separately if needed:

```bash
terraform -chdir=modules plan -destroy -var-file="dev.tfvars" -target=module.eks
```

## Configuration and Recovery

Both scripts define `TF_DIR`, `TF_VAR_FILE` (`dev.tfvars`) and `TF_BACKEND_CONFIG` (`dev.s3.tfbackend`) in the project-path section. Paths are resolved relative to the script, so invocation from other working directories is supported. `TF_AUTO_APPROVE` must be `true` or `false` and defaults to `false`. Authentication continues to use the existing `run_aws_auth.sh`.

If AWS reports node groups absent from state, verify account, region, backend and workspace before resolving the mismatch. Preserve `errored.tfstate` after persistence failures. Direct Terraform destroy commands bypass the script guard. The waiter timeout does not cancel AWS deletion.

Targeted teardown leaves module declarations in configuration, so a later full apply can recreate EKS and NAT. Targeted creation should be followed by a full plan when reviewing the rest of the project.

## Offline Tests

```bash
python3 -m unittest discover -s script/tests -v
```

Lifecycle tests use temporary directories and mock authentication, AWS CLI and Terraform commands. They cover sequencing, failures, untracked node groups, confirmation/cancellation and automatic approval. They do not create or delete AWS resources.
