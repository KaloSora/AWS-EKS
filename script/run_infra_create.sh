#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# AWS EKS - Terraform Create
#
# Local environment: macOS / Bash
# Usage:
#   ./script/run_infra_create.sh
#   TF_AUTO_APPROVE=true ./script/run_infra_create.sh
#
# Runbook:
#   1. Initialize/validate Terraform and check AWS node group state
#   2. Create module.eks and its required dependencies
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

# ------------------------------------------------------------
# Pre-check and authentication
# ------------------------------------------------------------

log "AWS EKS - CREATE"
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
# STEP 1 - Create EKS and Required Dependencies
# ------------------------------------------------------------

set -- terraform -chdir="$TF_DIR" apply \
    -target=module.eks \
    -var-file="$TF_VAR_FILE"
if [[ "$TF_AUTO_APPROVE" == "true" ]]; then
    set -- "$@" -auto-approve
fi

if ! run_step "1/1 - Create EKS and Required Dependencies" "$@"; then
    error "EKS apply failed. Preserve state/recovery files and inspect AWS node groups before retrying or destroying IAM roles."
fi

# ------------------------------------------------------------
# Final State and Access Summary
# ------------------------------------------------------------

log "Terraform State"
terraform -chdir="$TF_DIR" state list

log "Terraform Outputs"
terraform -chdir="$TF_DIR" output

log "CREATE COMPLETED"
echo "EKS and its Terraform dependencies have been deployed."
echo "Next step: configure kubectl using your authorized cluster administrator identity."
printf '  aws eks update-kubeconfig --region %s --name %s\n' "$EKS_REGION" "$EKS_CLUSTER_NAME"
echo "  kubectl get nodes"
echo "  kubectl get pods -n kube-system"
