#!/bin/bash
# 1. add secondary CIDR to VPC
# 2. create subnet under new CIDR
# 3. attach subnets to route tables to point them to NAT GWs

k get ds -n kube-system # aws-node is the CNI plugin
# can be customized by env vars and and ENI config CRDs
# amazon-k8s-cni:v1.6.1 must be in v 1.6 or higher

# https://docs.aws.amazon.com/eks/latest/userguide/cni-custom-network.html
# https://aws.github.io/aws-eks-best-practices/networking/vpc-cni/
# https://repost.aws/knowledge-center/eks-multiple-cidr-ranges
# https://docs.aws.amazon.com/eks/latest/userguide/cni-increase-ip-addresses.html
# https://docs.aws.amazon.com/eks/latest/userguide/calico.html

cluster_name="ekscluster"
cluster_stack_name="eksctl-$cluster_name-cluster"
region="us-east-1"
secondary_cidr="100.64.0.0/16"
subnet_a_cidr="100.64.0.0/19"
subnet_b_cidr="100.64.32.0/19"
subnet_c_cidr="100.64.64.0/19"

# check CNI plugin version"
kubectl describe daemonset aws-node --namespace kube-system | grep Image | cut -d "/" -f 2

vpc_id=`aws cloudformation describe-stack-resources --stack-name ${cluster_stack_name} --query "StackResources[?LogicalResourceId=='VPC'].PhysicalResourceId" --output text`
aws ec2 associate-vpc-cidr-block --vpc-id ${vpc_id} --cidr-block ${secondary_cidr}
sleep 5
aws ec2 describe-vpcs --vpc-ids $vpc_id --query 'Vpcs[*].CidrBlockAssociationSet[*].{CIDRBlock: CidrBlock, State: CidrBlockState.State}' --out table


nat_gateway_id=`aws ec2 describe-nat-gateways --query "NatGateways[?VpcId=='${vpc_id}'].NatGatewayId" --output text`

aws cloudformation deploy \
    --stack-name "$cluster_name-secondary-subnets" \
    --template-file cni_additional_subnets.json \
    --parameter-overrides \
        Region=${region} \
        VPCID=${vpc_id} \
        EKSClusterName=${cluster_name} \
        SubnetACidr=${subnet_a_cidr} \
        SubnetBCidr=${subnet_b_cidr} \
        SubnetCCidr=${subnet_c_cidr} \
        NATGatewayId=${nat_gateway_id}

cluster_security_group_id=$(aws eks describe-cluster --name $cluster_name --query cluster.resourcesVpcConfig.clusterSecurityGroupId --output text)

new_subnet_id_1=$(aws cloudformation describe-stacks --region $region --query "Stacks[?StackName=='$cluster_name-secondary-subnets'][].Outputs[?OutputKey=='SubnetIdA'].OutputValue" --output text)
new_subnet_id_2=$(aws cloudformation describe-stacks --region $region --query "Stacks[?StackName=='$cluster_name-secondary-subnets'][].Outputs[?OutputKey=='SubnetIdB'].OutputValue" --output text)
new_subnet_id_3=$(aws cloudformation describe-stacks --region $region --query "Stacks[?StackName=='$cluster_name-secondary-subnets'][].Outputs[?OutputKey=='SubnetIdC'].OutputValue" --output text)
az_1=$(aws ec2 describe-subnets --subnet-ids $new_subnet_id_1 --query 'Subnets[*].AvailabilityZone' --output text)
az_2=$(aws ec2 describe-subnets --subnet-ids $new_subnet_id_2 --query 'Subnets[*].AvailabilityZone' --output text)
az_3=$(aws ec2 describe-subnets --subnet-ids $new_subnet_id_3 --query 'Subnets[*].AvailabilityZone' --output text)

kubectl set env daemonset aws-node -n kube-system AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true
kubectl describe daemonset aws-node -n kube-system | grep ENI_CONFIG_ANNOTATION_DEF # set for production cluster
kubectl set env daemonset aws-node -n kube-system ENI_CONFIG_LABEL_DEF=topology.kubernetes.io/zone

cluster_security_group_id=$(aws eks describe-cluster --name $cluster_name --query cluster.resourcesVpcConfig.clusterSecurityGroupId --output text)

cat > "cni_eni_$az_1.yaml" <<EOF
apiVersion: crd.k8s.amazonaws.com/v1alpha1
kind: ENIConfig
metadata:
  name: $az_1
spec:
  securityGroups:
    - $cluster_security_group_id
  subnet: $new_subnet_id_1
EOF

cat > "cni_eni_$az_2.yaml" <<EOF
apiVersion: crd.k8s.amazonaws.com/v1alpha1
kind: ENIConfig
metadata:
  name: $az_2
spec:
  securityGroups:
    - $cluster_security_group_id
  subnet: $new_subnet_id_2
EOF

cat > "cni_eni_$az_3.yaml" <<EOF
apiVersion: crd.k8s.amazonaws.com/v1alpha1
kind: ENIConfig
metadata:
  name: $az_3
spec:
  securityGroups:
    - $cluster_security_group_id
  subnet: $new_subnet_id_3
EOF

k apply -f "cni_eni_$az_1.yaml"
k apply -f "cni_eni_$az_2.yaml"
k apply -f "cni_eni_$az_3.yaml"

kubectl get ENIConfigs

# then replace all worker nodes (can be terminated in EC2 console)

# if the following message will occur while starting a pod:
# Failed to create pod sandbox: rpc error: code = Unknown desc = failed to setup network for sandbox "xxx": plugin type="aws-cni" name="aws-cni" failed (add): add cmd: failed to assign an IP address to container


# eksctl get nodegroup --cluster "$cluster_name"
# eksctl delete nodegroup --cluster "$cluster_name" --name eks-node-group
# eksctl create nodegroup -f eks.yaml

# test with:
# k run -it --restart=Never --rm --image=busybox:latest -- busybox