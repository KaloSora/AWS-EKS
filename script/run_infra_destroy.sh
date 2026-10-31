#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# AWS EKS - Terraform Destroy
#
# Local environment: macOS / Bash
# Usage:
#   ./script/run_infra_destroy.sh
#   TF_AUTO_APPROVE=true ./script/run_infra_destroy.sh
#
# Destroy order:
#   1. EKS node group, then wait for AWS deletion confirmation
#   2. EKS control plane and IAM resources
#   3. NAT EC2 module resources
# ============================================================

# ------------------------------------------------------------
# Project paths
# ------------------------------------------------------------

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
TF_DIR="${PROJECT_ROOT}/modules"
TF_VAR_FILE="dev.tfvars"
TF_BACKEND_CONFIG="dev.s3.tfbackend"
TF_AUTO_APPROVE="${TF_AUTO_APPROVE:-false}"

# ------------------------------------------------------------
# Functions
# ------------------------------------------------------------

log() {
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
}

error() {
    echo
    echo "[ERROR] $1" >&2
    exit 1
}

run_step() {
    local step="$1"
    shift

    echo
    echo "------------------------------------------------------------"
    echo "STEP ${step}"
    echo "------------------------------------------------------------"
    echo "+ $*"

    "$@" || return $?

    echo "[PASS] STEP ${step}"
}

validate_boolean() {
    local name="$1"
    local value="$2"
    case "$value" in
        true|false) ;;
        *) error "${name} must be true or false, got: ${value}" ;;
    esac
}

pre_check() {
    local command_name
    for command_name in terraform aws jq; do
        command -v "$command_name" >/dev/null 2>&1 || \
            error "${command_name} command not found"
    done

    [[ -d "$TF_DIR" ]] || error "Terraform directory not found: ${TF_DIR}"
    [[ -f "${TF_DIR}/${TF_VAR_FILE}" ]] || error "Terraform variable file not found: ${TF_DIR}/${TF_VAR_FILE}"
    [[ -f "${TF_DIR}/${TF_BACKEND_CONFIG}" ]] || error "Terraform backend file not found: ${TF_DIR}/${TF_BACKEND_CONFIG}"
    [[ -f "${SCRIPT_DIR}/run_aws_auth.sh" ]] || error "AWS authentication script not found"
    [[ -f "${SCRIPT_DIR}/eks_lifecycle.sh" ]] || error "EKS lifecycle helper not found"
    validate_boolean "TF_AUTO_APPROVE" "$TF_AUTO_APPROVE"

    echo "Project root       : ${PROJECT_ROOT}"
    echo "Terraform directory: ${TF_DIR}"
    echo "Variable file      : ${TF_VAR_FILE}"
    echo "Backend config     : ${TF_BACKEND_CONFIG}"
    echo "Auto approve       : ${TF_AUTO_APPROVE}"
}

run_destroy() {
    local step="$1"
    local target="$2"

    run_step "${step}/3 - Destroy ${target}" \
        terraform -chdir="$TF_DIR" destroy \
        -target="$target" \
        -var-file="$TF_VAR_FILE" \
        -auto-approve || return $?

    echo "[PASS] ${target} destroyed"
}

# ------------------------------------------------------------
# Pre-check and authentication
# ------------------------------------------------------------

log "AWS EKS - DESTROY"
pre_check

# Source in this process so Terraform inherits the assumed-role credentials.
unset AWS_SESSION_TOKEN AWS_SECURITY_TOKEN
source "${SCRIPT_DIR}/run_aws_auth.sh"
source "${SCRIPT_DIR}/eks_lifecycle.sh"

# ------------------------------------------------------------
# Terraform Init and Validate
# ------------------------------------------------------------

log "Terraform Init"
terraform -chdir="$TF_DIR" init -backend-config="$TF_BACKEND_CONFIG"
echo "[PASS] Terraform initialization completed"

log "Terraform Validate"
terraform -chdir="$TF_DIR" validate
echo "[PASS] Terraform configuration is valid"

log "EKS State Check"
load_eks_context
assert_nodegroups_tracked
echo "AWS region         : ${EKS_REGION}"
echo "EKS cluster        : ${EKS_CLUSTER_NAME}"
echo "[PASS] AWS node groups match the current Terraform state"

# ------------------------------------------------------------
# Confirmation
# ------------------------------------------------------------

log "DESTROY WARNING"
echo "The following Terraform targets will be destroyed:"
echo "  1. module.eks.aws_eks_node_group.this and its dependents"
echo "  2. module.eks (control plane and IAM resources)"
echo "  3. module.ec2_nat_instance (EC2, EIP, ENI, IAM and private default routes)"
echo
echo "VPC, Internet Gateway, subnets, budget and S3 Gateway endpoint are retained."
echo "Remove workload-created load balancers and review persistent data first."
echo "This operation is DESTRUCTIVE."

if [[ "$TF_AUTO_APPROVE" != "true" ]]; then
    CONFIRM=""
    if ! read -r -p "Type 'destroy' to continue: " CONFIRM || [[ "$CONFIRM" != "destroy" ]]; then
        echo
        echo "Destroy cancelled."
        exit 0
    fi
fi

# ------------------------------------------------------------
# Destroy
# ------------------------------------------------------------

run_destroy "1" "module.eks.aws_eks_node_group.this"

log "Wait for AWS Node Group Deletion"
# A waiter/query failure stops execution before cluster roles or NAT are removed.
wait_for_nodegroups_deleted

run_destroy "2" "module.eks"
run_destroy "3" "module.ec2_nat_instance"

# ------------------------------------------------------------
# Final State
# ------------------------------------------------------------

log "Final Terraform State"
REMAINING="$(terraform -chdir="$TF_DIR" state list)"
if [[ -z "$REMAINING" ]]; then
    echo "[PASS] Terraform state is empty."
else
    echo "Remaining Terraform resources (retained infrastructure is expected):"
    echo "$REMAINING"
fi

log "DESTROY COMPLETED"
echo "EKS and NAT cleanup completed."
