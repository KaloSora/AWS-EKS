#!/bin/bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../modules"

# Source authentication in this process so Terraform inherits the role credentials.
unset AWS_SESSION_TOKEN AWS_SECURITY_TOKEN
source "${SCRIPT_DIR}/run_aws_auth.sh"

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

    "$@"

    echo "[PASS] STEP ${step}"
}

# ------------------------------------------------------------
# STEP 1 - Terraform Init
# ------------------------------------------------------------

log "Terraform Init"

terraform -chdir="$TERRAFORM_DIR" init -backend-config="dev.s3.tfbackend"

echo "[PASS] Terraform initialization completed"

# ------------------------------------------------------------
# Terraform Validate
# ------------------------------------------------------------

log "Terraform Validate"

terraform -chdir="$TERRAFORM_DIR" validate

echo "[PASS] Terraform configuration is valid"

# ------------------------------------------------------------
# STEP 2 - Create EKS and Required Dependencies
# ------------------------------------------------------------

log "Create EKS Managed Node Group Cluster"

run_step "2 - Create EKS" terraform -chdir="$TERRAFORM_DIR" apply \
    -var-file="dev.tfvars" \
    -target=module.eks
