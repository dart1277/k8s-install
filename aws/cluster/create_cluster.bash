#!/bin/bash
export KUBERNETES_VERSION="1.26"
export CLUSTER_NAME="ekscluster"
export KEY_PAIR_NAME="eks_key"
export KEY_FILE_NAME="$CLUSTER_NAME-nodegroup-ssh-key"
export AWS_REGION="us-east-1"
export ALB_SA_NAME="$CLUSTER_NAME-aws-load-balancer-controller"
export ADMIN_IPV4_ADDRESS="80.49.230.155"
# create ssh key
# ssh-keygen -t ed25519 -f "$KEY_FILE_NAME"
# aws ec2 import-key-pair --key-name "$KEY_PAIR_NAME" --public-key-material "file://./$KEY_FILE_NAME.pub"
# chmod 400 "./$KEY_FILE_NAME"
# if invalid base64 encoding error occurs run:
aws ec2 import-key-pair --key-name "$KEY_PAIR_NAME" --public-key-material "fileb://./$KEY_FILE_NAME.pub"


# update kubeconfig
# aws eks update-kubeconfig --name "$CLUSTER_NAME"

# https://www.stacksimplify.com/aws-eks/aws-loadbalancers/aws-eks-create-private-nodegroup/
# https://eksctl.io/usage/schema/

cat << EOF > eks.yaml
---
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: ${CLUSTER_NAME}
  region: ${AWS_REGION}
  version: "${KUBERNETES_VERSION}"

kubernetesNetworkConfig:
  ipFamily: IPv4 # or IPv6
  #cluster version must be => 1.21
  #vpc-cni addon version must be => 1.10.0
  #unmanaged nodegroups are not yet supported with IPv6 clusters
  #managed nodegroup creation is not supported with un-owned IPv6 clusters
  #vpc.NAT and serviceIPv4CIDR fields are created by eksctl for ipv6 clusters and thus, are not supported configuration options
  #AutoAllocateIPv6 is not supported together with IPv6

vpc:
  cidr: 10.0.0.0/16
  # https://eksctl.io/usage/vpc-cluster-access/
  # https://docs.aws.amazon.com/eks/latest/userguide/cluster-endpoint.html
  clusterEndpoints:
    publicAccess:  true
    privateAccess: true
  publicAccessCidrs:
    - "${ADMIN_IPV4_ADDRESS}/32" # does not seem to have effect, the cluster control plane is accessible from 0.0.0.0/0 after deployment
  # sharedNodeSecurityGroup: sg-0123456789
  # manageSharedNodeSecurityGroupRules: false
#  subnets:
#    private:
#      private-one:
#          id: "subnet-0153e560b3129a696"
  nat:
    gateway: Single # other options: HighlyAvailable, Disable, Single (default)

availabilityZones: ["${AWS_REGION}a", "${AWS_REGION}b", "${AWS_REGION}c"]

#nodeGroups:
#- name: ng-2
#  minSize: 1
#  maxSize: 5
#  desiredCapacity: 3
#  instancesDistribution:
#    maxPrice: 0.017
#    instanceTypes: ["m5.xlarge"]
#    onDemandPercentageAboveBaseCapacity: 0
#    spotInstancePools: 2
#  labels: { lifecycle: Ec2Spot } # required by ec2 spot termination handler

managedNodeGroups:
- name: eks-node-group
  instanceType: t2.micro
  minSize: 1
  maxSize: 6
  desiredCapacity: 3
  volumeSize: 30
  privateNetworking: true
  # spot: true
  iam:
  # https://eksctl.io/usage/iam-policies/
    withAddonPolicies:
      autoScaler: true # enable auto auto scaler, then install resource: https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/cloudprovider/aws/README.md
    attachPolicyARNs:
      - arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
      - arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
      - arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
      - arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess
      # - arn:aws:iam::1111111111:policy/kube2iam # add custom iam policy

#  subnets:
#    - private-one
  ssh:
    enableSsm: true # alternatively can use ssm
    allow: true
    publicKeyName: ${KEY_PAIR_NAME}
    # sourceSecurityGroupIds: sg-xx

# To enable all of the control plane logs, uncomment below:
# cloudWatch:
#  clusterLogging:
#    enableTypes: ["*"]

fargateProfiles:
#  - name: fp-default
#    selectors:
#      # All workloads in the "default" Kubernetes namespace will be
#      # scheduled onto Fargate:
#      - namespace: default
#      # All workloads in the "kube-system" Kubernetes namespace will be
#      # scheduled onto Fargate:
#      - namespace: kube-system
  - name: fp-dev
    selectors:
      # All workloads in the "dev" Kubernetes namespace matching the following
      # label selectors will be scheduled onto Fargate:
      - namespace: dev
        labels:
          env: dev
          checks: passed
# eksctl create fargateprofile -f eks.yaml
# eksctl get fargateprofile --cluster $CLUSTER_NAME -o yaml
# k run -it --restart=Never --rm --image=busybox:latest -l env=dev,checks=passed -n dev -- busybox2
EOF

# you can enable logging with 'eksctl utils update-cluster-logging --enable-types={SPECIFY-YOUR-LOG-TYPES-HERE (e.g. all)} --region=$AWS_REGION --cluster=$CLUSTER_NAME'

eksctl create cluster -f eks.yaml
eksctl utils associate-iam-oidc-provider --cluster="$CLUSTER_NAME" --approve

aws eks update-cluster-config \
    --region "$AWS_REGION" \
    --name "$CLUSTER_NAME" \
    --resources-vpc-config endpointPublicAccess=true,publicAccessCidrs="$ADMIN_IPV4_ADDRESS/32",endpointPrivateAccess=true

# write kube config:
# eksctl utils write-kubeconfig --cluster "$CLUSTER_NAME"

# to fix error: getting credentials: decoding stdout: no kind "ExecCredential" is registered for version "client.authentication.k8s.io/v1alpha1" in scheme "pkg/client/auth/exec/exec.go:62"
# caused by outdated version of aws-iam-authenticator, version 0.5.9 seems to work correctly as of k8s 1.26.2
# https://docs.aws.amazon.com/eks/latest/userguide/install-aws-iam-authenticator.html
# aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"
# kubectl version

# enable secret encryption using kms key
# eksctl utils enable-secrets-encryption --cluster="$CLUSTER_NAME" --key-arn=arn:aws:kms:us-west-2:<account>:key/<key> --encrypt-existing-secrets=false --region="$AWS_REGION"

# eksctl get nodegroup --cluster "$CLUSTER_NAME"
# eksctl delete nodegroup --cluster "$CLUSTER_NAME" --name eks-node-group
# eksctl create nodegroup -f eks.yaml
# eksctl scale nodegroup --cluster "$CLUSTER_NAME" --nodes 0 --nodes-min 0  --name eks-node-group
# eksctl utils nodegroup-health --cluster "$CLUSTER_NAME" --name eks-node-group

# eksctl delete cluster --name "$CLUSTER_NAME"

# kubectl get pods -n default | grep nginx | awk '{print $1}'
# re-run previous command
# kubectl delete pods -n default `!!`


# node termination handler (needed by unmanaged node groups) for spot instances can be installed by running (with kubernetes 1.25+):
# https://artifacthub.io/packages/helm/aws/aws-node-termination-handler
# helm repo add eks https://aws.github.io/eks-charts/
# helm upgrade --install --namespace kube-system --set nodeSelector.lifecycle=Ec2Spot --set rbac.pspEnabled=false aws-node-termination-handler eks/aws-node-termination-handler
# unmanaged nodes needs to have label of lifecycle=Ec2Spot set