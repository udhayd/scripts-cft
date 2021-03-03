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
    test_var()
    {
    [ -z "$1" ] && echo "Value is Empty" && exit 1
    }
    read -p "Enter the VPC_CIDR_BLOCK Eg:"10.0.0.0/16": " VPC_CIDR_BLOCK
    test_var "$VPC_CIDR_BLOCK"
    read -p "Enter the PUBLIC_SUBNET_CIDR Eg:"10.0.10.0/24,10.0.20.0/24": " PUBLIC_SUBNET_CIDR
    test_var "$PUBLIC_SUBNET_CIDR"
    read -p "Enter the PRIVATE_SUBNET_CIDR Eg:"10.0.100.0/24,10.0.200.0/24": " PRIVATE_SUBNET_CIDR
    test_var "$PRIVATE_SUBNET_CIDR"
    echo  "Executing Stack"
    echo ""
else
    usage
    exit
fi

#### Varible Initialization
echo "VPC_STACK_NAME=$2-vpc" >vars.sh
source vars.sh
set -ex

#### VPC Stack Creation
aws cloudformation deploy --no-fail-on-empty-changeset --template-file vpc.yaml --stack-name $VPC_STACK_NAME --parameter-overrides VpcCidr=$VPC_CIDR_BLOCK PublicSubnetCidr=$PUBLIC_SUBNET_CIDR PrivateSubnetCidr=$PRIVATE_SUBNET_CIDR  --capabilities CAPABILITY_NAMED_IAM 
