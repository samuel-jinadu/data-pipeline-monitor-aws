#!/bin/bash
ENV_FILE=${1:-environments/fakecloud.env}
source "$ENV_FILE"

REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com"
# Note: FakeCloud uses localhost in the URL, Real AWS uses amazonaws.com
if [ "$AWS_ENDPOINT_URL" == "http://localhost:4566" ]; then
    REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.localhost:4566"
fi

REPO_URI="${REGISTRY}/data-pipeline-monitor"

aws ecr create-repository --repository-name data-pipeline-monitor || true
aws ecr get-login-password | docker login --username AWS --password-stdin "$REGISTRY"
docker tag data-pipeline-monitor:latest "$REPO_URI:latest"
docker push "$REPO_URI:latest"