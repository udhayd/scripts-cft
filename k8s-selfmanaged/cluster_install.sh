#! /bin/bash

##################################################################################################################
####  Description: Script to install K8s Cluster                                                              ####
####  Version: 1.0v                                                                                           ####
####  Usage: ./cluster_install.sh 1.x.x                                                                       ####
##################################################################################################################

#set -e
### Variable Initilization
VER=$(echo $1 | cut -d'.'  -f1,2)
INTERNAL_IP=$(grep master /etc/hosts|tail -1| awk '{print $1}')


### Usage check
if [ $# -ne 1 ]
then
echo "Please provide clusterversion as parameter"
echo "Usage: $0 1.x.x"
exit 1
fi

### Configure Yum Repository
cat <<EOF >/etc/yum.repos.d/kubernetes.repo
#### Kubernetes Installation Repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v$VER/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v$VER/rpm/repodata/repomd.xml.key
##exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF
#yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

### Install Kubernetes & Container packages
if ! rpm -q kubelet kubeadm kubectl containerd
then
yum install -y kubeadm-$1 kubectl-$1 kubelet-$1 containerd --disableexcludes=kubernetes
mkdir -p /etc/containerd && containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
fi

### Configure Kernel modules
tee /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF

modprobe overlay 
modprobe br_netfilter

if [ ! -f /etc/sysctl.d/k8s.conf ]
then
cat <<EOF >  /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
EOF

setenforce 0
sed -i -E "s/SELINUX=[^ ]*/SELINUX=disabled/g" /etc/selinux/config
sed -i '/swap/d' /etc/fstab
swapoff -a
sysctl --system
fi

### Start/Enable Containerd & Kubelet Service
if rpm -q kubelet kubeadm kubectl containerd
then
   systemctl enable kubelet && systemctl start kubelet
   systemctl enable containerd && systemctl start containerd
   systemctl status containerd| grep 'Active:'
fi

### Install & configure crictl
if [ ! -f /usr/local/bin/crictl ]
then
   wget https://github.com/kubernetes-sigs/cri-tools/releases/download/v1.26.0/crictl-v1.26.0-linux-amd64.tar.gz
   tar zxvf crictl-v1.26.0-linux-amd64.tar.gz -C /usr/local/bin

   echo "==================================="
   echo "Config BEFORE change:"
   crictl config --set runtime-endpoint=unix:///run/containerd/containerd.sock --set image-endpoint=unix:///run/containerd/containerd.sock
   echo "==================================="
   echo "Config AFTER change:"
   cat /etc/crictl.yaml
fi