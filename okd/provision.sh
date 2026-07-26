#! /bin/bash

##################################################################################################################
####  Description: Wrapper Script to create a AWS Cloudformation Stack to create OKD Openshift Cluster UPI    ####
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
    echo "Executing Script"
    aws cloudformation list-exports|grep "MyVPCID" >/dev/null 2>&1
    if [ $? -ne 0 ]
    then
        echo ""
        echo "Network stack doesnt exist, Creating Network stack ..."
        cd ../vpc
        ./provision.sh -n $2
        echo ""
        cd ../okd
        echo ""
        echo "Creating OKD Stack ..."
    fi
    echo ""
    echo "Creating OKD Stack ..."
else
    usage
    exit
fi

#### Varible Initialization
source config.properties
CRED1=$AWS_ACCESS_KEY_ID
CRED2=$AWS_SECRET_ACCESS_KEY
echo "OKD_CONFIG_STACK_NAME=$2-okd-config" >vars.sh
echo "OKD_CL_STACK_NAME=$2-okd-cluster" >>vars.sh
source vars.sh
set -ex

#### okd Stack Creation
AMIID=$(aws ec2 describe-images --owners amazon --filters "Name=name,Values=RHEL-9*x86_64*" --query 'sort_by(Images, &CreationDate)[].ImageId' |tail -2|head -1|sed 's/"//g')
Image=$(echo -n $AMIID)

aws cloudformation deploy --template-file okd-config.yaml --stack-name $OKD_CONFIG_STACK_NAME --no-fail-on-empty-changeset --capabilities CAPABILITY_NAMED_IAM --parameter-overrides STK=$OKD_CONFIG_STACK_NAME CRED1=$CRED1 CRED2=$CRED2 ImageId=$Image HOSTZONE=$DOMAIN

aws cloudformation deploy --template-file okd-cluster.yaml --stack-name $OKD_CL_STACK_NAME --no-fail-on-empty-changeset --capabilities CAPABILITY_NAMED_IAM
