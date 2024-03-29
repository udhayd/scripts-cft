# K8S Cluster - Hardway

## Introduction:
Following Script creates 4 ec2 instances (master,worker1,worker2,nginx) to setup K8s cluster HardWay, provision.sh can be executed from AWS Cloudshell (or) gitbash.

## PREQUISITES: 
- aws cli to execute provision.sh script.

## To Create EC2 Instances for cluster Build
1. Clone a Git repository.
   ```sh
   git clone https://github.com/udhayd/scripts-cft
   ```
2. Execute Cloudformation Template.
   ```sh
   cd scripts-cft/k8s-hardway
   ./provision.sh -n "name of stack" &
   ```

## To Build k8s cluster
Please execute below steps to build k8s cluster. 

1. Login to Master node to setup k8s controlplane components.
   ```sh
   /root/cluster-configure.sh v1.23.0
   ```
2. Validate cluster status.
   ```sh
   kubectl cluster-info
   ```
3. Login to Master node to add worker nodes to k8s cluster build in step1.
   ```sh
   ssh worker1 bash -s < /root/cluster-workers.sh v1.23.0 
   ssh worker2 bash -s < /root/cluster-workers.sh v1.23.0 
   ```
4. Validate worker nodes status.
   ```sh
   kubectl get nodes
   ```

## To Destroy K8s cluster

1. To Detroy the Cloudformation template
   ```sh
   cd scripts-cft/k8s-hardway
   ./destroy.sh
   ```
