#!/bin/bash
kubectl get configmap aws-auth -n kube-system -o yaml
# add codebuild's service role (can be found in codebuild/details) and grant superuser permissions
eksctl create iamidentitymapping --cluster eks-acg --arn arn:xxx --username  api-deployment --group system:masters

# buildspec.yaml files
#version: 0.2
#
#env:
#  variables:
#    APP: inventory-api
#    ECR_URL: 750796802028.dkr.ecr.us-east-2.amazonaws.com
#    ECR_REPO_NAME: bookstore.inventory-api
#
#phases:
#  pre_build:
#    commands:
#      - source `pwd`/version
#      - COMMIT_ID_SHORT=`echo "${CODEBUILD_RESOLVED_SOURCE_VERSION}" | cut -c1-8`
#      - TAG=`echo "${MAJOR}.${MINOR}.${COMMIT_ID_SHORT}"`
#      - aws ecr get-login-password --region us-east-2 | docker login --username AWS --password-stdin ${ECR_URL}
#  build:
#    commands:
#      - docker build -t ${APP}:${TAG} -f src/Dockerfile src
#      - docker tag ${APP}:${TAG} ${ECR_URL}/${ECR_REPO_NAME}:${TAG}
#  post_build:
#    commands:
#      - docker push ${ECR_URL}/${ECR_REPO_NAME}:${TAG}

#version: 0.2
#
#env:
#  variables:
#    HELM_RELEASE_NAME: inventory-api-development
#    NAMESPACE: development
#    EKS_CLUSTER_NAME: eks-acg
#
#phases:
#  install:
#    commands:
#      - curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
#      - unzip awscliv2.zip
#      - ./aws/install
#      - curl -o kubectl https://amazon-eks.s3.us-west-2.amazonaws.com/1.16.8/2020-04-16/bin/linux/amd64/kubectl
#      - chmod +x kubectl
#      - mv ./kubectl /usr/local/bin/kubectl
#      - curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 > get_helm.sh
#      - chmod 700 get_helm.sh
#      - ./get_helm.sh
#  pre_build:
#    commands:
#      - source `pwd`/version
#      - COMMIT_ID_SHORT=`echo "${CODEBUILD_RESOLVED_SOURCE_VERSION}" | cut -c1-8`
#      - TAG=`echo "${MAJOR}.${MINOR}.${COMMIT_ID_SHORT}"`
#      - echo ${TAG}
#      - aws eks --region ${AWS_DEFAULT_REGION} update-kubeconfig --name ${EKS_CLUSTER_NAME}
#      - kubectl get nodes
#  build:
#    commands:
#      - cd infra/helm-v2
#      - helm upgrade --install --namespace ${NAMESPACE} ${HELM_RELEASE_NAME} -f values.yaml -f values.${NAMESPACE}.yaml --set image.tag=${TAG} .
#  post_build:
#    commands:
#      - echo Done