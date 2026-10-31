#!/bin/bash
# Shared, read-only checks. The caller initializes Terraform and AWS authentication.

load_eks_context() {
    local context
    context="$(terraform -chdir="$TERRAFORM_DIR" console -var-file="dev.tfvars" <<'HCL'
jsonencode({region = var.aws_region, cluster_name = "${var.aws_env}-eks"})
HCL
)" || return $?
    context="$(printf '%s\n' "$context" | jq -er 'fromjson')" || return $?
    EKS_REGION="$(printf '%s\n' "$context" | jq -er '.region | select(length > 0)')" || return $?
    EKS_CLUSTER_NAME="$(printf '%s\n' "$context" | jq -er '.cluster_name | select(length > 0)')" || return $?
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
    managed_groups="$(terraform -chdir="$TERRAFORM_DIR" show -json | jq -c \
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
