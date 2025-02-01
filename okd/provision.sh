#! /bin/bash

##################################################################################################################
####  Description: Wrapper Script to create a AWS Cloudformation Stack for Local Managed Kubernetes Cluster   ####
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
        echo "Network stack doesnt exist, Executing VPC Stack First ..."
        cd ../vpc
        ./provision.sh -n $2
        echo ""
        cd ../okd
	echo ""
        echo "Executing K8s Stack ..."
    fi
    echo ""
    echo "Executing K8s Stack ..."
else
    usage
    exit
fi

#### Varible Initialization
source config.properties
echo "EC2_STACK_NAME=$2-k8s" >vars.sh
source vars.sh
set -ex

#### K8s Stack Creation
AMIID=$(aws ec2 describe-images --owners amazon --filters "Name=name,Values=RHEL-9*x86_64*" --query 'sort_by(Images, &CreationDate)[].ImageId' |tail -2|head -1|sed 's/"//g')
Image=$(echo -n $AMIID)
aws cloudformation deploy --template-file k8s.yaml --stack-name $EC2_STACK_NAME --no-fail-on-empty-changeset --capabilities CAPABILITY_NAMED_IAM --parameter-overrides STK=$EC2_STACK_NAME  ImageId=$Image HOSTZONE=$DOMAIN
