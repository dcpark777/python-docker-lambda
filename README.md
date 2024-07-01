# python-docker-lambda

## Documentation
https://docs.aws.amazon.com/lambda/latest/dg/python-image.html

## Make commands
- Full build and deploy: `make deploy`
    - export `requirements.txt`
    - build Docker image
    - tag image and push to ECR
    - create lambda function using image
- Clean up: `make clean`
    - destroy lambda function
