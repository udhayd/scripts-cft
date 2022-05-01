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
rm vars.sh
