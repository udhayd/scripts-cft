# AWS EKS Cluster

## Introduction:
Following Script bootraps eks cluster in AWS Cloud , can be executed from AWS Cloudshell (or) gitbash.

## PREQUISITES: 
please execute below steps from aws cloud shell.
- aws cli to execute script.
- kubectl cli to access eks cluster.

## To Create eks cluster
$ git clone https://github.com/udhayd/scripts-cft

$ cd scripts-cft/eks

$ ./provision.sh -n "name of stack" &

## To Access the eks cluster
Please execute update kubeconfig to access eks cluster.

$ aws eks list-clusters --output text

$ aws eks --region region-code update-kubeconfig --name $CLUSTER_NAME

$ kubectl get nodes

## To Destroy eks cluster
$ ./destroy.sh
