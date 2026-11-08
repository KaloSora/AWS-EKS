#!/bin/bash
# Assume the infrastructure role in the caller's shell.
# Usage: source script/run_aws_auth.sh
# AWS_SESSION_DURATION_SECONDS defaults to 10800 (3 hours).
# Example: AWS_SESSION_DURATION_SECONDS=7200 ./script/run_infra_create.sh
# The target role must allow the requested duration; role chaining is limited
# to 3600 seconds. AWS failures stop authentication without a shorter retry.

# This file should contain account_id, access key, role name
source ~/aws_env.sh

AWS_SESSION_DURATION_SECONDS="${AWS_SESSION_DURATION_SECONDS-10800}"
if [[ ! "$AWS_SESSION_DURATION_SECONDS" =~ ^[1-9][0-9]{2,4}$ ]] ||
   (( AWS_SESSION_DURATION_SECONDS < 900 || AWS_SESSION_DURATION_SECONDS > 43200 )); then
  echo "AWS_SESSION_DURATION_SECONDS must be an integer from 900 to 43200 seconds." >&2
  return 1 2>/dev/null || exit 1
fi

CREDENTIALS_FILE="/tmp/aws_creds.json"

echo "Assuming $AWS_ROLE_NAME role..."
if ! aws sts assume-role \
  --role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${AWS_ROLE_NAME}" \
  --duration-seconds "$AWS_SESSION_DURATION_SECONDS" \
  --role-session-name "Terraform-$(date +%s)" > "$CREDENTIALS_FILE"; then
  echo "AssumeRole failed; credentials were not changed." >&2
  echo "Check role MaxSessionDuration; role chaining cannot exceed 3600 seconds." >&2
  return 1 2>/dev/null || exit 1
fi

export AWS_ACCESS_KEY_ID=$(jq -r '.Credentials.AccessKeyId' "$CREDENTIALS_FILE")
export AWS_SECRET_ACCESS_KEY=$(jq -r '.Credentials.SecretAccessKey' "$CREDENTIALS_FILE")
export AWS_SESSION_TOKEN=$(jq -r '.Credentials.SessionToken' "$CREDENTIALS_FILE")

# Health check
echo "Current identity:"
if ! aws sts get-caller-identity; then
  echo "Identity verification failed." >&2
  return 1 2>/dev/null || exit 1
fi

# Report the requested duration; this does not implement credential refresh.
echo "STS session duration: ${AWS_SESSION_DURATION_SECONDS} seconds (requested)"
