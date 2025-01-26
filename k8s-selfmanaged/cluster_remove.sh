#! /bin/bash

##################################################################################################################
####  Description: Script to Remove K8s Cluster                                                               ####
####  Version: 1.0v                                                                                           ####
####  Usage: ./cluster_remove.sh                                                                              ####
##################################################################################################################

#set -e
### To Remove Cluster
if rpm -q kubelet kubeadm kubectl containerd
then
   kubeadm reset -f
   systemctl stop containerd kubelet
   yum remove -y kubeadm  kubectl kubelet containerd
   rm  -fr /etc/kube* /var/lib/kube* /opt/cni* /etc/cni* /root/.kube /etc/crictl.yaml /usr/local/bin/crictl /etc/containerd
   echo -e "\n" "Rebooting Node"
   reboot
else
   echo "K8s Cluster not configured"
fi