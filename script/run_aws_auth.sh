#!/bin/bash
# assume-role.sh

# This file should contain account_id, access key, role name
source ~/aws_env.sh

CREDENTIALS_FILE="/tmp/aws_creds.json"

echo "Assuming $AWS_ROLE_NAME role..."
if ! aws sts assume-role \
  --role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${AWS_ROLE_NAME}" \
  --role-session-name "Terraform-$(date +%s)" > "$CREDENTIALS_FILE"; then
  echo "AssumeRole failed; credentials were not changed." >&2
  return 1 2>/dev/null || exit 1
fi

export AWS_ACCESS_KEY_ID=$(jq -r '.Credentials.AccessKeyId' $CREDENTIALS_FILE)
export AWS_SECRET_ACCESS_KEY=$(jq -r '.Credentials.SecretAccessKey' $CREDENTIALS_FILE)
export AWS_SESSION_TOKEN=$(jq -r '.Credentials.SessionToken' $CREDENTIALS_FILE)

# Health check
echo "Current identity:"
if ! aws sts get-caller-identity; then
  echo "Identity verification failed." >&2
  return 1 2>/dev/null || exit 1
fi

# Set timer for the session
echo "Credentials valid for 1 hour"