#!/bin/bash
export CLUSTER_NAME="ekscluster2"
export ALB_SA_NAME="$CLUSTER_NAME-aws-load-balancer-controller"

# or install https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html
# to creat nlb instead of classic ALB

curl -o lb-iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
echo "ALB IAM policy:"
cat lb-iam-policy.json | jq
aws iam create-policy --policy-name AWSLoadBalancerControllerIAMPolicy --policy-document file://lb-iam-policy.json
export PolicyARN=$(aws iam list-policies --query 'Policies[?PolicyName==`AWSLoadBalancerControllerIAMPolicy`].Arn' --output text)
echo "AWSLoadBalancerControllerIAMPolicy ARN:"
echo $PolicyARN

eksctl create iamserviceaccount \
   --cluster="$CLUSTER_NAME" \
   --namespace=kube-system \
   --name="$ALB_SA_NAME" \
   --attach-policy-arn=$PolicyARN \
   --override-existing-serviceaccounts \
   --approve

helm repo add eks https://aws.github.io/eks-charts
kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller//crds?ref=master"

helm upgrade -i "$ALB_SA_NAME" eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set serviceAccount.create=false \
  --set enableServiceMutatorWebhook=false \
  --set serviceAccount.name="$ALB_SA_NAME"

# verify ALB deployment
#kubectl logs -n kube-system "deployments/$ALB_SA_NAME"
#kubectl -n kube-system get deployments

# deploy k8s dashboard
# export DASHBOARD_VERSION="v2.6.1"
# kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/${DASHBOARD_VERSION}/aio/deploy/recommended.yaml
# kubectl proxy --port=8080 --address=0.0.0.0 --disable-filter=true &
# append at the end of URL
# /api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/
# aws eks get-token --cluster-name "$CLUSTER_NAME" | jq -r '.status.token'

# https://catalog.us-east-1.prod.workshops.aws/workshops/ed1a8610-c721-43be-b8e7-0f300f74684e/en-US/eks/deploy-container
# get ELB FQDN
# ELB=$(kubectl get service loadbalanced-service-name -o json | jq -r '.status.loadBalancer.ingress[].hostname')
# curl -m3 -v $ELB

#cat << EOF > mythical-ingress.yaml
#apiVersion: networking.k8s.io/v1
#kind: Ingress
#metadata:
#  name: "$CLUSTER_NAME-ingress-eks"
#  annotations:
#    kubernetes.io/ingress.class: alb
#    alb.ingress.kubernetes.io/scheme: internet-facing
#  labels:
#    app: myapp
#spec:
#  rules:
#    - http:
#        paths:
#          - path: /mysfits/*/like
#            pathType: ImplementationSpecific
#            backend:
#              service:
#                name: "mythical-mysfits-like"
#                port:
#                  number: 80
#          - path: /*
#            pathType: ImplementationSpecific
#            backend:
#              service:
#                name: "mythical-mysfits-nolike"
#                port:
#                  number: 80
#EOF


