#!/bin/bash
# Shared lifecycle checks and local kubeconfig setup.
# The caller initializes Terraform and AWS authentication.

configure_kubeconfig() (
    umask 077
    mkdir -p -- "$(dirname -- "$KUBECONFIG_FILE")" || return $?
    aws eks update-kubeconfig \
        --region "$EKS_REGION" \
        --name "$EKS_CLUSTER_NAME" \
        --alias "$EKS_CLUSTER_NAME" \
        --kubeconfig "$KUBECONFIG_FILE" || return $?
    chmod 600 "$KUBECONFIG_FILE" || return $?
)

load_storage_state() {
    local state
    state="$(terraform -chdir="$TF_DIR" show -json)" || return $?
    STORAGE_RELEASE_TRACKED="$(printf '%s\n' "$state" | jq -er '
        [.. | objects | select(.type? == "helm_release") |
          select((.address? // "") | startswith("module.eks_storage."))] |
        if length > 0 then "true" else "false" end')" || return $?
    EFS_FILE_SYSTEM_ID="$(printf '%s\n' "$state" | jq -r '
        [.. | objects | select(.type? == "aws_efs_file_system") |
          select((.address? // "") | startswith("module.eks_efs.")) |
          .values.id] | if length == 0 then "" elif length == 1 then .[0]
          else error("Multiple EFS file systems in module.eks_efs; review cleanup scope") end')" || return $?
}

check_cluster_presence() {
    local error_file
    error_file="$(mktemp)" || return $?
    if aws eks describe-cluster --name "$EKS_CLUSTER_NAME" --region "$EKS_REGION" \
        --query cluster.name --output text --no-cli-pager >/dev/null 2> "$error_file"; then
        EKS_CLUSTER_PRESENT=true
    elif grep -q '(ResourceNotFoundException)' "$error_file"; then
        EKS_CLUSTER_PRESENT=false
    else
        cat "$error_file" >&2
        rm -f "$error_file"
        return 1
    fi
    rm -f "$error_file"
}

load_eks_context() {
    local context
    context="$(terraform -chdir="$TF_DIR" console -var-file="$TF_VAR_FILE" <<'HCL'
jsonencode({region = var.aws_region, cluster_name = "${var.aws_env}-eks", nat_instance_enable = var.nat_instance_enable})
HCL
)" || return $?
    context="$(printf '%s\n' "$context" | jq -er 'fromjson')" || return $?
    EKS_REGION="$(printf '%s\n' "$context" | jq -er '.region | select(length > 0)')" || return $?
    EKS_CLUSTER_NAME="$(printf '%s\n' "$context" | jq -er '.cluster_name | select(length > 0)')" || return $?
    NAT_INSTANCE_ENABLE="$(printf '%s\n' "$context" | jq -er '.nat_instance_enable | if type == "boolean" then tostring else error("nat_instance_enable must be a boolean") end')" || return $?
}

# Report configuration intent; it does not prove deployed NAT state/readiness.
print_nat_status() {
    local operation="$1"
    echo "NAT instance enabled: ${NAT_INSTANCE_ENABLE} (Terraform configuration)"
    if [ "$operation" = "create" ]; then
        if [ "$NAT_INSTANCE_ENABLE" = "true" ]; then
            echo "NAT EC2, EIP, ENI, IAM and private default routes are enabled dependencies."
            echo "Verify NAT cloud-init readiness and private-node egress after deployment."
        else
            echo "NAT creation is disabled; private nodes require alternate AWS API and image-registry connectivity."
            echo "The S3 Gateway endpoint alone is insufficient for node bootstrap and CSI operations."
            echo "If NAT is already tracked, this apply can remove it and its private default routes; review the plan."
        fi
    else
        echo "NAT cleanup remains the final destroy step, regardless of this setting."
        echo "Any NAT resources tracked in state are targeted, including when creation is disabled."
        echo "If none are tracked, Terraform has no NAT resources to remove; untracked AWS resources are not discovered."
    fi
}

list_eks_nodegroups() {
    local result error_file
    error_file="$(mktemp)" || return $?
    if result="$(aws eks list-nodegroups \
        --cluster-name "$EKS_CLUSTER_NAME" \
        --region "$EKS_REGION" \
        --output json --no-cli-pager 2> "$error_file")"; then
        rm -f "$error_file"
        printf '%s\n' "$result" | jq -ce '.nodegroups | select(type == "array")'
    else
        # Only a genuinely absent cluster is treated as having no node groups.
        # Authentication/authorization/network errors must stop the caller.
        if grep -q '(ResourceNotFoundException)' "$error_file"; then
            rm -f "$error_file"
            printf '[]\n'
        else
            cat "$error_file" >&2
            rm -f "$error_file"
            return 1
        fi
    fi
}

assert_nodegroups_tracked() {
    local managed_groups untracked
    EKS_NODEGROUPS="$(list_eks_nodegroups)" || return $?
    managed_groups="$(terraform -chdir="$TF_DIR" show -json | jq -c \
        --arg cluster "$EKS_CLUSTER_NAME" \
        '[.. | objects | select(.type? == "aws_eks_node_group") | .values? |
          select(.cluster_name? == $cluster) | .node_group_name |
          select(type == "string")] | unique')" || return $?
    untracked="$(printf '%s\n' "$EKS_NODEGROUPS" | jq -c --argjson managed "$managed_groups" '. - $managed')" || return $?
    if [ "$untracked" != '[]' ]; then
        echo "[ERROR] AWS node groups are missing from the current Terraform state: $untracked" >&2
        echo "Stop here: verify the account/backend/workspace and any errored.tfstate before deleting EKS IAM roles." >&2
        echo "Resolve the untracked node groups explicitly; this script does not delete them or edit state automatically." >&2
        return 1
    fi
}

wait_for_nodegroups_deleted() {
    local group remaining
    while IFS= read -r group; do
        echo "Waiting for node group deletion: $group"
        aws eks wait nodegroup-deleted \
            --cluster-name "$EKS_CLUSTER_NAME" \
            --nodegroup-name "$group" \
            --region "$EKS_REGION" || return $?
    done < <(printf '%s\n' "$EKS_NODEGROUPS" | jq -r '.[]')
    remaining="$(list_eks_nodegroups)" || return $?
    if [ "$remaining" != '[]' ]; then
        echo "[ERROR] Node groups still exist: $remaining. Cluster, IAM role and NAT cleanup stopped." >&2
        return 1
    fi
}

# Detect all tracked ingress-module resources, including partial IAM-only applies.
load_ingress_state() {
    local state
    state="$(terraform -chdir="$TF_DIR" show -json)" || return $?
    INGRESS_MODULE_TRACKED="$(printf '%s\n' "$state" | jq -er '
        [.. | objects | select(.mode? == "managed") |
          select((.address? // "") | startswith("module.eks_ingress."))] |
        if length > 0 then "true" else "false" end')" || return $?
}

# Read-only gate: platform and application ingress cleanup must complete while the Controller works.
# No workload deletion, AWS resource deletion, retry or finalizer stripping here.
assert_ingress_cleanup_complete() {
    local resources remaining api_resources aws_resources
    if [[ "$EKS_CLUSTER_PRESENT" == "true" ]]; then
        resources="$(kubectl --kubeconfig "$KUBECONFIG_FILE" --context "$EKS_CLUSTER_NAME" \
            --request-timeout=30s get ingresses.networking.k8s.io,services --all-namespaces -o json)" || return $?
        remaining="$(printf '%s\n' "$resources" | jq -ce '
            .items | if type != "array" then error("Invalid Kubernetes list") else
              [.[] | select(.kind == "Ingress" or
                (.kind == "Service" and .spec.type == "LoadBalancer")) |
                {kind, namespace: .metadata.namespace, name: .metadata.name}] end')" || return $?
        if [[ "$remaining" != '[]' ]]; then
            echo "[ERROR] Remove application Ingresses and LoadBalancer Services before teardown: $remaining" >&2
            return 1
        fi

        # Discover the CRD rather than treating arbitrary API errors as absence.
        api_resources="$(kubectl --kubeconfig "$KUBECONFIG_FILE" --context "$EKS_CLUSTER_NAME" \
            --request-timeout=30s api-resources --api-group=elbv2.k8s.aws --cached=false -o name)" || return $?
        if [[ "$api_resources" == *"targetgroupbindings.elbv2.k8s.aws"* ]]; then
            resources="$(kubectl --kubeconfig "$KUBECONFIG_FILE" --context "$EKS_CLUSTER_NAME" \
                --request-timeout=30s get targetgroupbindings.elbv2.k8s.aws --all-namespaces -o json)" || return $?
            remaining="$(printf '%s\n' "$resources" | jq -ce '
                .items | if type != "array" then error("Invalid TargetGroupBinding list") else
                  [.[] | {namespace: .metadata.namespace, name: .metadata.name}] end')" || return $?
            if [[ "$remaining" != '[]' ]]; then
                echo "[ERROR] TargetGroupBindings still exist; keep the Controller running until cleanup completes: $remaining" >&2
                return 1
            fi
        fi
    fi

    # AWS CLI auto-pagination is retained. This gate covers cluster-tagged LBs
    # and target groups, including those orphaned outside Terraform state.
    aws_resources="$(aws resourcegroupstaggingapi get-resources \
        --region "$EKS_REGION" \
        --tag-filters "Key=elbv2.k8s.aws/cluster,Values=${EKS_CLUSTER_NAME}" \
        --resource-type-filters elasticloadbalancing:loadbalancer elasticloadbalancing:targetgroup \
        --query 'ResourceTagMappingList[].ResourceARN' --output json --no-cli-pager)" || return $?
    remaining="$(printf '%s\n' "$aws_resources" | jq -ce '
        if type == "array" and all(.[]; type == "string") then .
        else error("Invalid AWS load balancer inventory") end')" || return $?
    if [[ "$remaining" != '[]' ]]; then
        echo "[ERROR] Cluster-tagged AWS load balancers/target groups remain: $remaining" >&2
        echo "Keep the Controller, nodes and IAM permissions available; complete cleanup before rerunning teardown." >&2
        return 1
    fi
    if [[ "$EKS_CLUSTER_PRESENT" == "true" ]]; then
        echo "[PASS] Kubernetes ingress inventory is empty."
    else
        echo "Kubernetes ingress inventory unavailable: cluster is absent."
    fi
    echo "[PASS] No cluster-tagged AWS load balancers or target groups found."
    echo "Review untagged resources and residual security groups separately; stop controllers that could recreate ingress resources."
}

# Include partial namespace creation; fail closed if state cannot be read.
load_app_state() {
    local state
    state="$(terraform -chdir="$TF_DIR" show -json)" || return $?
    APP_MODULE_TRACKED="$(printf '%s\n' "$state" | jq -er '
        [.. | objects | select(.mode? == "managed") |
          select((.address? // "") | startswith("module.app."))] |
        if length > 0 then "true" else "false" end')" || return $?
}

# Include partial applies and fail closed if state cannot be read.
load_component_state() {
    local state
    state="$(terraform -chdir="$TF_DIR" show -json)" || return $?
    CICD_MODULE_TRACKED="$(printf '%s\n' "$state" | jq -er '
        any(.. | objects | select(.mode? == "managed");
          (.address? // "") | startswith("module.eks_cicd.")) | tostring')" || return $?
    KARPENTER_MODULE_TRACKED="$(printf '%s\n' "$state" | jq -er '
        any(.. | objects | select(.mode? == "managed");
          (.address? // "") | startswith("module.karpenter.")) | tostring')" || return $?
}
