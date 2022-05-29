#!/bin/bash
###########################################################################################################
####       Description : Script to remove the CFT Stacks from var.env file                           ###### 
####       Version : 1.0v                                                                            ######
####       Usage : ./destroy.sh                                                                      ######
###########################################################################################################
set -ux

#### Variable file check
if [ ! -f vars.sh ]
then
echo -e '\n \t' "vars.sh File not found , Please create vars.sh file with appropriate variables"
exit 1
fi

source vars.sh
source cluster.conf
ACCID=$(aws sts get-caller-identity --query "Account" --output text)
OIDC_PROVIDER=$(aws iam list-open-id-connect-providers --query OpenIDConnectProviderList --output text)

#### Deleting individuals CF stacks
if  grep STACK_NAME vars.sh >/dev/null 2>&1
then
aws cloudformation delete-stack --stack-name $WORKERNODE_STACK_NAME
aws cloudformation wait stack-delete-complete --stack-name  $WORKERNODE_STACK_NAME
aws cloudformation delete-stack --stack-name $CLUSTER_STACK_NAME
aws cloudformation wait stack-delete-complete --stack-name $CLUSTER_STACK_NAME
echo -e '\n \t' "EKS Stack has been removed"
else
   echo -e '\n \t' "No Stack Name Found in vars.sh file"
fi
aws iam detach-role-policy --policy-arn arn:aws:iam::$ACCID:policy/${CLUSTER_NAME}_EKS_EBS_Policy --role-name ${CLUSTER_NAME}_EKS_EBS_role
aws iam delete-policy --policy-arn arn:aws:iam::$ACCID:policy/${CLUSTER_NAME}_EKS_EBS_Policy
aws iam delete-open-id-connect-provider --open-id-connect-provider-arn $OIDC_PROVIDER
aws iam delete-role --role-name ${CLUSTER_NAME}_EKS_EBS_role
rm vars.sh
