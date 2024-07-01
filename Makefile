aws_region = us-east-2
aws_account := $(shell aws sts get-caller-identity --query Account --output text)
ecr_repo_name = python-docker-lambda
image_name = $(ecr_repo_name)
ecr_repo_uri := $(shell aws ecr describe-repositories --repository-name $(ecr_repo_name) --region $(aws_region) --query 'repositories[0].repositoryUri' --output text)
lambda_iam_role_name = lambda-role
lambda_iam_role_arn := $(shell aws iam get-role --role-name $(lambda_iam_role_name) --region $(aws_region) --query 'Role.Arn' --output text)
lambda_function_name = python-docker-lambda-function
ecr_image_uri := $(shell aws ecr describe-images --repository-name $(ecr_repo_name) --region $(aws_region) --query 'imageDetails[*].imageTags[0]' --output json | jq --arg v `aws ecr describe-repositories --repository-name $(ecr_repo_name) --region $(aws_region) --query 'repositories[0].repositoryUri' --output text` '.[] | ($$v + ":" + .)' | jq -r '.')

.PHONY: help
help:
	@echo "Usage: make [target]"

.PHONY: wait
wait:
	@echo "Waiting for lambda function to be updated..."
	@aws lambda wait function-updated --function-name $(lambda_function_name) --region $(aws_region)

.PHONY: deploy
deploy: export build docker-deploy lambda-deploy wait test-lambda # Deploy the full stack

.PHONY: clean
clean: destroy-lambda # Clean up the lambda function
	@echo "All cleaned up!"

.PHONY: build
build: export # Build the docker image
	@docker build --platform linux/amd64 -t python-docker-lambda:test .
	@docker image ls | grep python-docker-lambda

.PHONY: export
export: # Export the requirements.txt file
	@poetry export -f requirements.txt --output requirements.txt --without-hashes

.PHONY: describe
describe: # Describe all parameters
	@echo "AWS Account: $(aws_account)"
	@echo "AWS Region: $(aws_region)"
	@echo "ECR Repo URI: $(ecr_repo_uri)"
	@echo "Image Name: $(image_name)"
	@echo "Image URI: $(ecr_image_uri)"

.PHONY: docker-deploy
docker-deploy: # Tag and push the docker image to ECR
	@echo "Tagging and pushing image to ECR..."
	@docker tag $(image_name):test $(ecr_repo_uri):latest
	@docker push $(ecr_repo_uri):latest

.PHONY: lambda-deploy
lambda-deploy: # Deploy the lambda function
	@echo "Deploying lambda function..."
	@aws lambda create-function \
	--function-name $(lambda_function_name) \
	--package-type Image \
	--code ImageUri=$(ecr_image_uri) \
	--role $(lambda_iam_role_arn) \
	--region $(aws_region) | jq -r '.FunctionArn'

.PHONY: destroy-lambda
destroy-lambda:
	@echo "Destroying lambda function $(lambda_function_name)..."
	@aws lambda delete-function --function-name $(lambda_function_name) --region $(aws_region)

.PHONY: test-lambda
test-lambda: # Test the lambda function
	@echo "Invoking lambda function..."
	@aws lambda invoke --region $(aws_region) --function-name $(lambda_function_name) response.json | jq -r '.StatusCode'

.PHONY: create-ecr
create-ecr: # Create ECR repository. Only needs to be run when creating a new repository.
	@echo "Creating ECR repository..."
	@echo $(aws_account) && \
	aws ecr get-login-password --region $(aws_region) | docker login --username AWS --password-stdin $${AWS_ACCOUNT}.dkr.ecr.$(aws_region).amazonaws.com && \
	aws ecr create-repository --repository-name $(ecr_repo_name) --region $(aws_region) --image-scanning-configuration scanOnPush=true --image-tag-mutability MUTABLE

.PHONY: create-role
create-role: # Create IAM role. Only needs to be run when creating a new role.
	@echo "Creating role..."
	@aws iam create-role --region $(aws_region) --role-name $(lambda_iam_role_name)  --assume-role-policy-document file://infra/trust-policy.json 	