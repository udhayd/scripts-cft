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

#### To validate the k8s property file
prop_validate ()
{
if [ ! $(cat config.properties|grep -v '#'|grep $1) ]
then
echo "$1 property not defined in config.properties file ,Please define !"
exit 255
elif [ -z $(cat config.properties|grep -v '#'|grep $1|awk -F'=' '{print $2}') ]
then
echo "$1 property is null Please set ! "
exit 255
fi
}
configfile_validate () 
{
if [ ! -f config.properties ]
then
echo "config.properties file doesn't Exist, Please create with version tag. Eg: version=1.19 "
exit 255
fi
prop_validate version
prop_validate mtype
prop_validate wtype
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
	cd vpc
        ./provision.sh -n $2-vpc
	echo ""
	cd ../ 
        configfile_validate
	echo "Executing K8s Stack ..."
	echo ""
    fi
    echo ""
    configfile_validate
    echo "Executing K8s Stack ..."
else
    usage
    exit
fi

#### Varible Initialization
echo "EC2_STACK_NAME=$2-k8s
ROUTE_STACK_NAME=$2-route53" >vars.sh
ver=$(cat config.properties|grep -v '#'|grep version|awk -F'=' '{print $2}')
mtyp=$(cat config.properties|grep -v '#'|grep mtype|awk -F'=' '{print $2}')
wtyp=$(cat config.properties|grep -v '#'|grep wtype|awk -F'=' '{print $2}')
source vars.sh
set -ex

#### K8s Stack Creation
aws cloudformation deploy --template-file k8s.yaml --stack-name $EC2_STACK_NAME --no-fail-on-empty-changeset --capabilities CAPABILITY_IAM --parameter-overrides STK=$EC2_STACK_NAME  VER=$ver MTYPE=$mtyp WTYPE=$wtyp 
