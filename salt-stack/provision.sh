#! /bin/bash

##################################################################################################################
####  Description: Wrapper Script to create a AWS Cloudformation Stack for Local Managed Saltstack            ####
####  Version: 1.0v                                                                                           ####
####  Usage: ./provision.sh -n stackname                                                                      ####
##################################################################################################################


#### Function for help
usage() {
    echo "Usage: $0 [options]"
    
    echo " -n, --name  name of stack"
}

#### To validate the Arguments
if [ $# -eq 2 ]
then
    echo "Executing Stack"
    echo ""
else
    usage
    exit
fi

#### Varible Initialization
echo "EC2_STACK_NAME=$2-salt" >vars.sh
source vars.sh
set -ex

#### K8s Stack Creation
aws cloudformation deploy --template-file salt.yaml --stack-name $EC2_STACK_NAME --no-fail-on-empty-changeset --capabilities CAPABILITY_IAM
