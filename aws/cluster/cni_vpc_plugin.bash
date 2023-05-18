#!/bin/bash
# 1. add secondary CIDR to VPC
# 2. create subnet under new CIDR
# 3. attach subnets to route tables to point them to NAT GWs

k get ds -n kube-system # aws-node is the CNI plugin
# can be customized by env vars and and ENI config CRDs
# amazon-k8s-cni:v1.6.1 must be in v 1.6 or higher

# https://docs.aws.amazon.com/eks/latest/userguide/cni-custom-network.html

cluster_stack_name="eksctl-eks-ekscluster"
region="us-east-2"
cluster_name="ekscluster"
secondary_cidr="100.64.0.0/16"
subnet_a_cidr="100.64.0.0/19"
subnet_b_cidr="100.64.32.0/19"
subnet_c_cidr="100.64.64.0/19"

vpc_id=`aws cloudformation describe-stack-resources --stack-name ${cluster_stack_name} --query "StackResources[?LogicalResourceId=='VPC'].PhysicalResourceId" --output text`
aws ec2 associate-vpc-cidr-block --vpc-id ${vpc_id} --cidr-block ${secondary_cidr}
sleep 5

nat_gateway_id=`aws ec2 describe-nat-gateways --query "NatGateways[?VpcId=='${vpc_id}'].NatGatewayId" --output text`

aws cloudformation deploy \
    --stack-name secondary-subnets \
    --template-file subnets.json \
    --parameter-overrides \
        Region=${region} \
        VPCID=${vpc_id} \
        EKSClusterName=${cluster_name} \
        SubnetACidr=${subnet_a_cidr} \
        SubnetBCidr=${subnet_b_cidr} \
        SubnetCCidr=${subnet_c_cidr} \
        NATGatewayId=${nat_gateway_id}

kubectl set env daemonset aws-node -n kube-system AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true
# kubectl set env daemonset aws-node -n kube-system ENI_CONFIG_LABEL_DEF=failure-domain.beta.kubernetes.io/zone
kubectl set env daemonset aws-node -n kube-system ENI_CONFIG_LABEL_DEF=topology.kubernetes.io/zone
cluster_security_group_id=$(aws eks describe-cluster --name $cluster_name --query cluster.resourcesVpcConfig.clusterSecurityGroupId --output text)

# TODO adust subnet names

subnet_id_1=$(aws cloudformation describe-stack-resources --stack-name my-eks-custom-networking-vpc \
    --query "StackResources[?LogicalResourceId=='PrivateSubnet01'].PhysicalResourceId" --output text)
subnet_id_2=$(aws cloudformation describe-stack-resources --stack-name my-eks-custom-networking-vpc \
    --query "StackResources[?LogicalResourceId=='PrivateSubnet02'].PhysicalResourceId" --output text)

subnet_id_3=""

az_1=$(aws ec2 describe-subnets --subnet-ids $subnet_id_1 --query 'Subnets[*].AvailabilityZone' --output text)
az_2=$(aws ec2 describe-subnets --subnet-ids $subnet_id_2 --query 'Subnets[*].AvailabilityZone' --output text)
az_3=""

cat >$az_1.yaml <<EOF
apiVersion: crd.k8s.amazonaws.com/v1alpha1
kind: ENIConfig
metadata:
  name: $az_1
spec:
  securityGroups:
    - $cluster_security_group_id
  subnet: $new_subnet_id_1
EOF

cat >$az_2.yaml <<EOF
apiVersion: crd.k8s.amazonaws.com/v1alpha1
kind: ENIConfig
metadata:
  name: $az_2
spec:
  securityGroups:
    - $cluster_security_group_id
  subnet: $new_subnet_id_2
EOF

cat >$az_3.yaml <<EOF
apiVersion: crd.k8s.amazonaws.com/v1alpha1
kind: ENIConfig
metadata:
  name: $az_3
spec:
  securityGroups:
    - $cluster_security_group_id
  subnet: $new_subnet_id_3
EOF

# then replace all worker nodes (can be terminated in EC2 console)