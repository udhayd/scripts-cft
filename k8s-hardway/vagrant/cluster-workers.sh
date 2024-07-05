#! /bin/bash
##################################################################################################
##### Description: Script to configure worker Nodes to join kubernetes cluster               #####
##### Usage: ./cluster-workers.sh                                                            #####
##### Version: 1.0                                                                           #####
##################################################################################################

set -ev
### Variable Initialization
DIR="$HOME/$$"
HOSTNAME=$(hostname)
ETCD_NAME=$(hostname -s)
MASTER_1=$(grep master /etc/hosts|tail -1|awk '{print $1}')
WORKER_1=$(grep worker1 /etc/hosts|tail -1|awk '{print $1}')
WORKER_2=$(grep worker2 /etc/hosts|tail -1|awk '{print $1}')
INTERNAL_IP=$(grep $HOSTNAME /etc/hosts|tail -1|awk '{print $1}')
LOADBALANCER=$(grep master /etc/hosts|tail -1|awk '{print $1}')
SERVICE_CIDR=10.96.0.0/24
POD_CIDR=10.244.0.0/16
CLUSTER_DNS=$(echo $SERVICE_CIDR | awk 'BEGIN {FS="."} ; { printf("%s.%s.%s.10", $1, $2, $3) }')
API_SERVICE=$(echo $SERVICE_CIDR | awk 'BEGIN {FS="."} ; { printf("%s.%s.%s.1", $1, $2, $3) }')
OS_VERSION=$(rpm -E %{rhel})
source cluster.conf
export KUBERNETES_VERSION COREDNS_VERSION ETCD_VERSION CONTAINERD_VERSION KUBERNETES_CNI
RPM_FILE="containerd.io-${CONTAINERD_VERSION}-3.1.el${OS_VERSION}.x86_64.rpm"


#### To validate cluster version property
property_validate ()
{
if [ ! $(cat cluster.conf|grep -v '#'|grep $1) ]
then
echo "$1 property not defined in cluster.conf file ,Please define !"
exit 255
elif [ -z $(cat cluster.conf|grep -v '#'|grep $1|awk -F'=' '{print $2}') ]
then
echo "$1 property is null Please set ! "
exit 255
fi
}


### To Validate cluster config file
{
if [ ! -f cluster.conf ]
then
echo "cluster.conf file doesn't Exist, Please create a file with cluster version."
exit 255
fi
for i in KUBERNETES_VERSION COREDNS_VERSION ETCD_VERSION CONTAINERD_VERSION KUBERNETES_CNI
do
property_validate $i
done
}


### Step1 Install Container Engine

echo -e "\n" "Step1.1 ====> Configure kernel modules"
{
tee /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF

cat  >/etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
EOF

  modprobe overlay
  modprobe br_netfilter
  sed -i '/swap/d' /etc/fstab
  swapoff -a
  sysctl --system
}

echo -e "\n" "Step1.2 ====> Installing Containerd"
  mkdir $DIR && cd $DIR
  curl -OLk  https://download.docker.com/linux/centos/${OS_VERSION}/x86_64/stable/Packages/${RPM_FILE}
  curl -kOL https://github.com/containernetworking/plugins/releases/download/${KUBERNETES_CNI}/cni-plugins-linux-amd64-${KUBERNETES_CNI}.tgz
  mkdir -p /opt/cni/bin && { cd /opt/cni/bin;tar -xzvf $DIR/cni-plugins-linux-amd64-${KUBERNETES_CNI}.tgz; }
  cd $DIR
  yum install -y ipvsadm ipset container-selinux
  rpm -ihv ${RPM_FILE}
  mkdir -p /etc/containerd
  containerd config default | sed 's/SystemdCgroup = false/SystemdCgroup = true/' | sudo tee /etc/containerd/config.toml
  systemctl enable containerd && systemctl restart containerd


### Step2 Download and Install Worker Binaries
echo -e "\n" "Step2.1 ====> Download and Install Worker Binaries"
  wget --no-check-certificate https://dl.k8s.io/release/${KUBERNETES_VERSION}/bin/linux/amd64/{kubelet,kubectl}
  mkdir -p /var/lib/kubelet /etc/kubernetes/pki /var/run/kubernetes
  chmod +x kubelet kubectl
  mv kubelet kubectl /usr/local/bin/


### Step3 Configure Kubelet
echo -e "\n" "Step3.1 ====> Configure Kubelet"
  mv $HOME/${HOSTNAME}.key $HOME/${HOSTNAME}.crt /etc/kubernetes/pki/
  mv $HOME/${HOSTNAME}.kubeconfig /var/lib/kubelet/kubelet.kubeconfig
  mv $HOME/ca.crt  /etc/kubernetes/pki/
  chown root:root /etc/kubernetes/pki/*
  chmod 600 /etc/kubernetes/pki/*
  chown root:root /var/lib/kubelet/*
  chmod 600 /var/lib/kubelet/*

cat <<EOF | sudo tee /var/lib/kubelet/kubelet-config.yaml
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
  x509:
    clientCAFile: /etc/kubernetes/pki/ca.crt
authorization:
  mode: Webhook
containerRuntimeEndpoint: unix:///var/run/containerd/containerd.sock
clusterDomain: cluster.local
clusterDNS:
- ${CLUSTER_DNS}
cgroupDriver: systemd
resolvConf: /etc/resolv.conf
runtimeRequestTimeout: "15m"
tlsCertFile: /etc/kubernetes/pki/${HOSTNAME}.crt
tlsPrivateKeyFile: /etc/kubernetes/pki/${HOSTNAME}.key
registerNode: true
EOF

cat <<EOF | sudo tee /etc/systemd/system/kubelet.service
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=containerd.service
Requires=containerd.service

[Service]
ExecStart=/usr/local/bin/kubelet \\
  --config=/var/lib/kubelet/kubelet-config.yaml \\
  --kubeconfig=/var/lib/kubelet/kubelet.kubeconfig \\
  --container-runtime=remote \\
  --container-runtime-endpoint=unix:///var/run/containerd/containerd.sock \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF


### Step4 Start Worker Services

echo -e "\n" "Step4.1 ====> Start Worker Services"
  systemctl daemon-reload
  systemctl enable kubelet  && { systemctl start kubelet;systemctl status kubelet|grep 'Active: active'; }
