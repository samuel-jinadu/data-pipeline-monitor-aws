#!/bin/bash
# Load environment variables
ENV_FILE=${1:-../../environments/fakecloud.env}
source "$ENV_FILE"

aws iam create-role \
    --role-name StreamlitAppTaskRole \
    --assume-role-policy-document file://ecs-trust-policy.json || true # Ignore if role already exists

aws iam put-role-policy \
    --role-name StreamlitAppTaskRole \
    --policy-name S3ReadOnlyPolicy \
    --policy-document file://s3-read-policy.json

aws iam get-role --role-name StreamlitAppTaskRole --query 'Role.Arn' --output text > StreamlitAppTaskRoleARN