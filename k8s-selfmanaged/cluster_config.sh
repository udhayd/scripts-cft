#! /bin/bash

##################################################################################################################
####  Description: Script to Configure K8s Cluster                                                            ####
####  Version: 1.0v                                                                                           ####
####  Usage: ./cluster_config.sh 1.x.x                                                                        ####
##################################################################################################################

set -e
### Variable Initilization
VER=$1
INTERNAL_IP=$(grep master /etc/hosts|tail -1| awk '{print $1}')

### Usage check
if [ $# -ne 1 ]
then
echo "Please provide clusterversion as parameter"
echo "Usage: $0 1.x.x"
exit 1
fi

### K8s Cluster Initialization
kubeadm init --pod-network-cidr=10.244.0.0/16  --kubernetes-version=$VER --ignore-preflight-errors all
if [ $? -eq 0 ]
then
   mkdir -p /root/.kube
   cp -i /etc/kubernetes/admin.conf /root/.kube/config
   chown $(id -u):$(id -g) /root/.kube/config
   export KUBECONFIG=/etc/kubernetes/admin.conf
   kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml
   #kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
else
   echo "Cluster Initialization Failed"
fi