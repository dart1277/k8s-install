#!/bin/bash
export REPO_NAME="aws-ecr-inventory"
export REGION="us-east-1"
aws ecr create-repository --repository-name "$REPO_NAME" --image-tag-mutability IMMUTABLE --image-scanning-configuration  scanOnPush=true --encryption-configuration encryptionType=AES256 --region "$REGION"

export ECR_REPO_URI=$(aws ecr describe-repositories --query "repositories[]" --output json --no-cli-pager | jq -r ".[].repositoryUri" | grep "$REPO_NAME")



aws ecr get-login-password --region "$REGION" | \
docker login --username AWS --password-stdin "$ECR_REPO_URI"

d image ls $ECR_REPO_URI

export D_IMG_NAME="stable/inventory-api"
export D_IMG_TAG="1.0"

 docker build -t "$D_IMG_NAME:$D_IMG_TAG" .
 docker tag "$D_IMG_NAME:$D_IMG_TAG" "$ECR_REPO_URI:$D_IMG_TAG"
 docker push "$ECR_REPO_URI:$D_IMG_TAG"
 docker rmi "$ECR_REPO_URI:$D_IMG_TAG"

#aws ecr get-login-password \
#     --region "$REGION" | helm registry login \
#     --username AWS \
#     --password-stdin aws_account_id.dkr.ecr.region.amazonaws.com

export APP_NAME="$(echo $D_IMG_NAME | tr '/' "-")"
export APP_PORT=5001
cat << EOF > "$APP_NAME.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: "${APP_NAME}"
spec:
  selector:
    matchLabels:
      app: "${APP_NAME}"
  template:
    metadata:
      labels:
        app: "${APP_NAME}"
    spec:
      containers:
      - image: "${ECR_REPO_URI}:${D_IMG_TAG}"
        name: "${APP_NAME}"
        ports:
        - containerPort: ${APP_PORT}
          name: http
EOF