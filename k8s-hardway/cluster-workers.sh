#! /bin/bash
##################################################################################################
##### Description: Script to configure worker Nodes to join kubernetes cluster               #####
##### Usage: ./configure-workernodes.sh                                                      #####
##### Version: 1.0                                                                           #####
##################################################################################################

### Variable Initialization
KUBE_VERSION=$1
export AZ=$(curl http://169.254.169.254/latest/meta-data/placement/availability-zone 2>/dev/null)
export AWS_DEFAULT_REGION=$(echo $AZ| sed 's/.$//g')
INTERNAL_IP=$(ip addr show eth0 | grep "inet " | awk '{print $2}' | cut -d / -f 1)
MASTER_1=$(grep master1 /etc/hosts|awk '{print $1}')
WORKER_1=$(grep worker1 /etc/hosts|awk '{print $1}')
WORKER_2=$(grep worker2 /etc/hosts|awk '{print $1}')
HOSTNAME=$(hostname)
ETCD_NAME=$(hostname -s)
LOADBALANCER=$(aws ec2 describe-instances --query 'Reservations[*].Instances[*].[PublicIpAddress,Tags[?Key==`Name`].Value|[0],LaunchTime,State.Name]' --output text|column -t|grep nginx|awk '{print $1}')
SERVICE_CIDR=10.96.0.0/24
POD_CIDR=10.244.0.0/16
CLUSTER_DNS=$(echo $SERVICE_CIDR | awk 'BEGIN {FS="."} ; { printf("%s.%s.%s.10", $1, $2, $3) }')
API_SERVICE=$(echo $SERVICE_CIDR | awk 'BEGIN {FS="."} ; { printf("%s.%s.%s.1", $1, $2, $3) }')

### Script Execution Validation
if [ $# -ne 1 ]
then
    echo "Usage: $0 v1.x.x"
    exit 1
fi


### Step1 Install Container Engine
echo -e "\n" "Step1 ====> Installing Containerd"
  yum install -y containerd kubernetes-cni ipvsadm ipset
  mkdir -p /etc/containerd
  containerd config default | sed 's/SystemdCgroup = false/SystemdCgroup = true/' | sudo tee /etc/containerd/config.toml
  systemctl restart containerd


### Step2 Download and Install Worker Binaries
echo -e "\n" "Step2 ====> Download and Install Worker Binaries"
  wget -q https://dl.k8s.io/release/${KUBE_VERSION}/bin/linux/amd64/kube-proxy https://dl.k8s.io/release/${KUBE_VERSION}/bin/linux/amd64/kubelet 
  mkdir -p /var/lib/kubelet /var/lib/kube-proxy /var/lib/kubernetes/pki /var/run/kubernetes
  chmod +x kube-proxy kubelet
  mv kube-proxy kubelet /usr/local/bin/


### Step3 Configure Kubelet
echo -e "\n" "Step3.1 ====> Configure Kubelet"
  mv ${HOSTNAME}.key ${HOSTNAME}.crt /var/lib/kubernetes/pki/
  mv ${HOSTNAME}.kubeconfig /var/lib/kubelet/kubelet.kubeconfig
  mv ca.crt /var/lib/kubernetes/pki/
  mv kube-proxy.crt kube-proxy.key /var/lib/kubernetes/pki/
  chown root:root /var/lib/kubernetes/pki/*
  chmod 600 /var/lib/kubernetes/pki/*
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
      clientCAFile: /var/lib/kubernetes/pki/ca.crt
  authorization:
    mode: Webhook
  containerRuntimeEndpoint: unix:///var/run/containerd/containerd.sock
  clusterDomain: cluster.local
  clusterDNS:
    - ${CLUSTER_DNS}
  cgroupDriver: systemd
  resolvConf: /etc/resolv.conf
  runtimeRequestTimeout: "15m"
  tlsCertFile: /var/lib/kubernetes/pki/${HOSTNAME}.crt
  tlsPrivateKeyFile: /var/lib/kubernetes/pki/${HOSTNAME}.key
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


### Step4 Configure Kube Proxy
echo -e "\n" "Step4.1 ====> Configure Kube Proxy"
  mv kube-proxy.kubeconfig /var/lib/kube-proxy/

  cat <<EOF | sudo tee /var/lib/kube-proxy/kube-proxy-config.yaml
  kind: KubeProxyConfiguration
  apiVersion: kubeproxy.config.k8s.io/v1alpha1
  clientConnection:
    kubeconfig: /var/lib/kube-proxy/kube-proxy.kubeconfig
  mode: ipvs
  clusterCIDR: ${POD_CIDR}
  EOF
  
  cat <<EOF | sudo tee /etc/systemd/system/kube-proxy.service
  [Unit]
  Description=Kubernetes Kube Proxy
  Documentation=https://github.com/kubernetes/kubernetes
  
  [Service]
  ExecStart=/usr/local/bin/kube-proxy \\
    --config=/var/lib/kube-proxy/kube-proxy-config.yaml
  Restart=on-failure
  RestartSec=5
  
  [Install]
  WantedBy=multi-user.target
  EOF

echo -e "\n" "Step4.2 ====> Start Worker Services"
  sudo systemctl daemon-reload
  sudo systemctl enable kubelet kube-proxy
  sudo systemctl start kubelet kube-proxy