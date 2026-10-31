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
# STEP 2 - Destroy EKS Before Its NAT Dependency
# ------------------------------------------------------------

log "Destroy EKS Managed Node Group Cluster"

echo "Remove workload-created load balancers and storage before proceeding."
echo "Review each Terraform destroy plan; each step requires confirmation."

run_step "2 - Destroy EKS" terraform -chdir="$TERRAFORM_DIR" destroy \
    -var-file="dev.tfvars" \
    -target=module.eks

# ------------------------------------------------------------
# STEP 3 - Destroy NAT EC2 and Its Module Resources
# ------------------------------------------------------------

log "Destroy NAT EC2 Instance"

run_step "3 - Destroy NAT EC2" terraform -chdir="$TERRAFORM_DIR" destroy \
    -var-file="dev.tfvars" \
    -target=module.ec2_nat_instance

log "EKS and NAT cleanup completed"
