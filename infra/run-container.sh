#!/bin/bash
# Load environment variables
ENV_FILE=${1:-../environments/fakecloud.env}
source "$ENV_FILE"

aws ecs create-cluster --cluster-name data-pipeline-cluster || true

ROLE_NAME="StreamlitAppTaskRole"
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"

# Dynamically set the image URL based on environment (FakeCloud vs AWS)
if [ "$AWS_ENDPOINT_URL" == "http://localhost:4566" ]; then
    IMAGE_URL="${ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.localhost:4566/data-pipeline-monitor:latest"
else
    IMAGE_URL="${ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/data-pipeline-monitor:latest"
fi

# Create the log group (FakeCloud and AWS require this for the awslogs driver)
aws logs create-log-group --log-group-name /ecs/data-pipeline-monitor || true

TASK_DEF=$(cat <<EOF
{
  "family": "data-pipeline-monitor-task",
  "networkMode": "bridge",
  "executionRoleArn": "${ROLE_ARN}",
  "containerDefinitions": [
    {
      "name": "streamlit-app",
      "image": "${IMAGE_URL}",
      "essential": true,
      "portMappings": [
        { "containerPort": 8501, "hostPort": 8501, "protocol": "tcp" }
      ],
      "environment": [
        { "name": "AWS_ENDPOINT_URL", "value": "${AWS_ENDPOINT_URL}" },
        { "name": "AWS_ACCESS_KEY_ID", "value": "${AWS_ACCESS_KEY_ID}" },
        { "name": "AWS_SECRET_ACCESS_KEY", "value": "${AWS_SECRET_ACCESS_KEY}" },
        { "name": "AWS_REGION", "value": "${AWS_DEFAULT_REGION}" }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/data-pipeline-monitor",
          "awslogs-region": "${AWS_DEFAULT_REGION}",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]
}
EOF
)

echo "$TASK_DEF" > task-def.json
aws ecs register-task-definition --cli-input-json file://task-def.json
aws ecs run-task --cluster data-pipeline-cluster --task-definition data-pipeline-monitor-task --count 1