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
VPC_CIDR_BLOCK=10.10.0.0/20
PUBLIC_SUBNET_CIDR="10.10.1.0/24,10.10.2.0/24"
PRIVATE_SUBNET_CIDR="10.10.11.0/24,10.10.12.0/24"
echo "VPC_STACK_NAME=$2-vpc" >vars.sh
source vars.sh
set -ex

#### VPC Stack Creation
aws cloudformation deploy --no-fail-on-empty-changeset --template-file vpc.yaml --stack-name $VPC_STACK_NAME --parameter-overrides VpcCidr=$VPC_CIDR_BLOCK PublicSubnetCidr=$PUBLIC_SUBNET_CIDR PrivateSubnetCidr=$PRIVATE_SUBNET_CIDR  --capabilities CAPABILITY_NAMED_IAM 
