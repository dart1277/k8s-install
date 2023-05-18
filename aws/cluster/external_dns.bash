#!/bin/bash
export CLUSTER_NAME="ekscluster"
export EXT_DNS_SA_NAME="external-dns"
export APP_NAMESPACE="default"
export EXT_DNS_NAMESPACE="external-dns"
export ROOT_DOMAIN="cmcloudlab861.info"
export DOMAIN_CERT_ARN="arn:aws:acm:us-east-1:792300178540:certificate/337bbe94-f700-4e63-bd21-1cded5848aff"

# review hosted zone id details
export ZONE_ID=$(aws route53 list-hosted-zones-by-name --output json \
  --dns-name "$ROOT_DOMAIN." --query HostedZones[0].Id --out text)

# show ns records for hosted zone
aws route53 list-resource-record-sets --output text \
 --hosted-zone-id $ZONE_ID --query \
 "ResourceRecordSets[?Type == 'NS'].ResourceRecords[*].Value | []" | tr '\t' '\n'


kubectl create namespace "$EXT_DNS_NAMESPACE"
kubectl label namespaces "$EXT_DNS_NAMESPACE" name="$EXT_DNS_NAMESPACE" --overwrite=true
aws iam create-policy --policy-name "ExternalDNSUpdatesPolicy" --policy-document file://external_dns_policy.json

# example: arn:aws:iam::XXXXXXXXXXXX:policy/AllowExternalDNSUpdates
export EXT_DNS_POLICY_ARN=$(aws iam list-policies \
 --query 'Policies[?PolicyName==`ExternalDNSUpdatesPolicy`].Arn' --output text)

eksctl create iamserviceaccount \
   --cluster="$CLUSTER_NAME" \
   --namespace="$EXT_DNS_NAMESPACE" \
   --name="$EXT_DNS_SA_NAME" \
   --attach-policy-arn="$EXT_DNS_POLICY_ARN" \
   --override-existing-serviceaccounts \
   --approve

# external dns pods may need to be deleted if SA IAM permissions are not picked up by external-dns pod
helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
helm upgrade --namespace "$EXT_DNS_NAMESPACE" --install external-dns external-dns/external-dns

# https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/aws.md



cat << EOF > ext_dns_app_test.yaml
---
apiVersion: v1
kind: Service
metadata:
  name: nginx
  annotations:
    external-dns.alpha.kubernetes.io/hostname: "${ROOT_DOMAIN}"
    external-dns.alpha.kubernetes.io/ttl: "10"
    service.beta.kubernetes.io/aws-load-balancer-ssl-cert: "${DOMAIN_CERT_ARN}"
    service.beta.kubernetes.io/aws-load-balancer-backend-protocol: "http"
    service.beta.kubernetes.io/aws-load-balancer-ssl-ports: "https"
spec:
  type: LoadBalancer
  ports:
  - port: 80
    name: http
    targetPort: 80
  - port: 443
    name: https
    targetPort: 80
  selector:
    app: nginx
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
spec:
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - image: nginx
        name: nginx
        ports:
        - containerPort: 80
          name: http
EOF

kubectl apply -f ext_dns_app_test.yaml --namespace "$APP_NAMESPACE"