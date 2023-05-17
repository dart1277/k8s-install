#!/bin/bash
helm del --namespace development $(helm ls --namespace development | grep deployed | awk '{print $1}')
# delete manually added iam policies to serviceaccount roles
# k get  mesh -n development
# k delete mesh dev-mesh -n development
# delete secondary subnets
# delete dns certs
# clear all ecr images used
