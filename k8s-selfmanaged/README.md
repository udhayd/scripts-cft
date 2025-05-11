# K8S Cluster - Kubeadm Installation

## Introduction:
Following Script creates 4 ec2 instances (master,worker1,worker2,nginx) to setup K8s cluster through kubeadm setup, provision.sh can be executed from AWS Cloudshell (or) gitbash.

## PREQUISITES: 
- aws cli to execute provision.sh script.

## To Create CFT stack for cluster Build
1. Clone a Git repository.
   ```sh
   git clone https://github.com/udhayd/scripts-cft
   ```
2. Configure AWS Credentials.
3. Execute Cloudformation template.
   ```sh
   cd scripts-cft/k8s-selfmanaged
   ./provision.sh -n "name of stack" &
   ```

## To Build k8s cluster
Please execute below steps to build k8s cluster. 

1. Login to Master node to setup k8s controlplane components.
   ```sh
   cd /root
   ./cluster_build.sh 1.29.15
   ```
2. Validate cluster status.
   ```sh
   kubectl cluster-info
   kubectl get nodes
   ```

## To Destroy CFT stack

1. To Detroy the Cloudformation stack
   ```sh
   cd scripts-cft/k8s-selfmanaged
   ./destroy.sh
   ```