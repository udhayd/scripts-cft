#! /bin/bash

##################################################################################################################
####  Description: Wrapper Script to create a AWS Cloudformation Stack for VPC,IGW,Subnet,NATGW,Routes	      ####
####  Version: 1.0v                                                                                           ####
####  Usage: ./provision.sh -n stackname  								      ####
##################################################################################################################


#### Function for help
usage() {
    echo "Usage: $0 [options]"
    
    echo " -n, --name  name of stack"
}

#### To validate the Arguments
if [ $# -eq 2 ]
then
    echo  "Executing Stack"
    echo ""
else
    usage
    exit
fi

#### Varible Initialization
echo "VPC_STACK_NAME=$2-vpc" >vars.sh
source vpc.conf
source vars.sh
set -ex

#### VPC Stack Creation
aws cloudformation deploy --no-fail-on-empty-changeset --template-file vpc.yaml --stack-name $VPC_STACK_NAME --parameter-overrides VpcCidr=$VPC_CIDR_BLOCK PublicSubnetCidr=$PUBLIC_SUBNET_CIDR PrivateSubnetCidr=$PRIVATE_SUBNET_CIDR  --capabilities CAPABILITY_NAMED_IAM 
