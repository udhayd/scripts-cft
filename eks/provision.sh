#!/bin/bash

##################################################################################################################
####  Description: Wrapper Script to create a AWS Cloudformation Stack for EKS Cluster & WorkerNodes          ####
####  Version: 1.0v                                                                                           ####
####  Usage: ./provision.sh -n stackname  								      ####
##################################################################################################################

#### Function for help
usage() {
    echo "Usage: $0 [options]"
    
    echo " -n, --name  name of stack"
}
source eks.sh

#### To validate the Arguments
if [ $# -ne 2 ]
then
   usage
   exit
fi

#### Verify eks tools
eks_verify_tools_installed

set -x
echo -e "\n" "Please refer log file $2.log"
exec >$2.log 2>&1

#### To validate AWS Credentials
aws cloudformation list-exports|grep "MyVPCID" >/dev/null 2>&1
if [ $? -ne 0 ]
then
   echo ""
   echo "Network stack doesnt exist, Executing VPC Stack First ..."
   cd ../vpc
   ./provision.sh -n $2-vpc
   echo ""
   cd ../eks
fi
echo -e '\n \t' "Executing Stack"
echo -e '\n \t' ""

#### Variable Initialization
set -e
echo "CLUSTER_STACK_NAME=$2-cluster" >vars.sh
source vars.sh
source cluster.conf

#### Create Cluster
aws cloudformation deploy --no-fail-on-empty-changeset --template-file ekscluster.yaml --stack-name $CLUSTER_STACK_NAME --capabilities CAPABILITY_IAM --parameter-overrides EKSClusterName=$CLUSTER_NAME KubernetesVersion=$KUBERNETES_VERSION \
    NodeInstanceType=$WORKER_INSTANCE_TYPE NodeAutoScalingGroupMinSize=$MIN_NUM_NODES \
    NodeAutoScalingGroupMaxSize=$MAX_NUM_NODES  NodeVolumeSize=$WORKER_NODE_VOL_SIZE \
    NodeAutoScalingGroupDesiredCapacity=$NUM_NODES ManagedNode=$EKS_MANAGED_NODE_GROUP \
    NodeGroupName=$NODE_GROUP_NAME    

export AWS_PAGER=""
if ! aws eks describe-cluster --name dev-cluster --output text|grep CLUSTERLOGGING|grep -i true  >/dev/null 2>&1
then
aws eks update-cluster-config --name $CLUSTER_NAME --logging '{"clusterLogging":[{"types":["api","audit","authenticator","controllerManager","scheduler"],"enabled":true}]}' 
fi

aws eks wait cluster-active --name $CLUSTER_NAME

#### Node IAM Role 
export NODE_INSTANCE_ROLE_ARN=$(aws cloudformation --output=text list-exports --query "Exports[?Name==\`${CLUSTER_NAME}-NodeInstanceRoleARN\`].Value")

#### Update kubeconfig
eks_configure_kubeconfig

#### Update aws-auth settings for UnManaged WorkerNode
cat <<EOF >auth.yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
    - rolearn: ${NODE_INSTANCE_ROLE_ARN}
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
EOF
if [ $EKS_MANAGED_NODE_GROUP = "false" ] 
then
kubectl apply -f auth.yaml
fi
rm auth.yaml

#### Install EBS CSI Driver
#bash ebs-csi.sh
