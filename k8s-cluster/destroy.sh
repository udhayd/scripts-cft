#!/bin/bash
###########################################################################################################
####       Description : Script to remove the CFT Stacks from var.sh file                            ###### 
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

#### Deleting individuals CF stacks
if  grep STACK_NAME vars.sh >/dev/null 2>&1
then
   for i in $(grep STACK_NAME vars.sh|awk -F'=' '{print $2}')
   do
   aws cloudformation delete-stack --stack-name $i
   done
else
   echo -e '\n \t' "No Stack Name Found in vars.sh file"
fi
rm vars.sh
