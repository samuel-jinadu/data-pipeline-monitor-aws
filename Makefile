.PHONY: help setup-data deploy-iam deploy-image-fakecloud deploy-image-aws deploy-ecs deploy-all

help:
	@echo "Available commands:"
	@echo "  make setup-data             - Generate data and upload to FakeCloud S3"
	@echo "  make deploy-iam             - Create the IAM Role and Policy"
	@echo "  make deploy-image-fakecloud - Build, tag, and push Docker image to FakeCloud ECR"
	@echo "  make deploy-image-aws       - Build, tag, and push Docker image to Real AWS ECR"
	@echo "  make deploy-ecs             - Register the Task Definition and run the ECS Task"
	@echo "  make deploy-all             - Run the full FakeCloud pipeline"

setup-data:
	cd streamlit-app/data && ./gen.sh && ./upload.sh ../../environments/fakecloud.env

deploy-iam:
	cd infra/policies && ./apply.sh ../../environments/fakecloud.env

deploy-image-fakecloud:
	./infra/push-image.sh environments/fakecloud.env

deploy-image-aws:
	./infra/push-image.sh environments/aws.env

deploy-ecs:
	./infra/run-container.sh environments/fakecloud.env

deploy-all: setup-data deploy-iam deploy-image-fakecloud deploy-ecs