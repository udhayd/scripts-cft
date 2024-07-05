#! /bin/bash
##################################################################################################
##### Description: Script to configure master Nodes to setup kubernetes cluster              #####
##### Usage: ./cluster-configure.sh                                                          #####
##### Version: 1.0                                                                           #####
##################################################################################################

set -ev
### Variable Initialization
DIR="$HOME/$$"
ETCD_NAME=$(hostname -s)
HOSTNAME=$(hostname)
MASTER_1=$(grep master /etc/hosts|tail -1|awk '{print $1}')
WORKER_1=$(grep worker1 /etc/hosts|tail -1|awk '{print $1}')
WORKER_2=$(grep worker2 /etc/hosts|tail -1|awk '{print $1}')
INTERNAL_IP=$(grep $HOSTNAME /etc/hosts|tail -1|awk '{print $1}')
LOADBALANCER=$(grep master /etc/hosts|tail -1|awk '{print $1}')
SERVICE_CIDR=10.96.0.0/24
POD_CIDR=10.244.0.0/16
CLUSTER_DNS=$(echo $SERVICE_CIDR|awk 'BEGIN {FS="."} ; { printf("%s.%s.%s.10", $1, $2, $3) }')
API_SERVICE=$(echo $SERVICE_CIDR|awk 'BEGIN {FS="."} ; { printf("%s.%s.%s.1", $1, $2, $3) }')
OS_VERSION=$(rpm -E %{rhel})
source cluster.conf
export KUBERNETES_VERSION COREDNS_VERSION ETCD_VERSION CONTAINERD_VERSION KUBERNETES_CNI NERDCTL_VERSION
RPM_FILE="containerd.io-${CONTAINERD_VERSION}-3.1.el${OS_VERSION}.x86_64.rpm"



### To validate cluster version property
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
for i in KUBERNETES_VERSION COREDNS_VERSION ETCD_VERSION CONTAINERD_VERSION KUBERNETES_CNI NERDCTL_VERSION
do
property_validate $i
done
}


### Step1 Kube Client tool & Container Engine Installation

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


echo -e "\n" "Step1.2 ====> Installing Containerd,CNI,Nerdctl"
{
  mkdir $DIR && cd $DIR
  wget --no-check-certificate "https://github.com/containerd/nerdctl/releases/download/v${NERDCTL_VERSION}/nerdctl-${NERDCTL_VERSION}-linux-amd64.tar.gz" -O /tmp/nerdctl.tar.gz
  curl -OLk  https://download.docker.com/linux/centos/${OS_VERSION}/x86_64/stable/Packages/${RPM_FILE}
  curl -kOL https://github.com/containernetworking/plugins/releases/download/${KUBERNETES_CNI}/cni-plugins-linux-amd64-${KUBERNETES_CNI}.tgz
  mkdir -p /opt/cni/bin && { cd /opt/cni/bin;tar -xzvf $DIR/cni-plugins-linux-amd64-${KUBERNETES_CNI}.tgz; }
  cd $DIR
  tar -xzvf /tmp/nerdctl.tar.gz && { mv nerdctl /usr/local/bin/;mkdir /etc/nerdctl; }

cat >/etc/nerdctl/nerdctl.toml <<EOF
    # https://github.com/containerd/nerdctl/blob/master/docs/config.md
    namespace      = "k8s.io"
    cgroup_manager = "systemd"
EOF

  yum install -y ipvsadm ipset container-selinux
  rpm -ihv ${RPM_FILE}
  mkdir -p /etc/containerd
  containerd config default | sed 's/SystemdCgroup = false/SystemdCgroup = true/' | sudo tee /etc/containerd/config.toml
  systemctl enable containerd && systemctl restart containerd
}


echo -e "\n" "Step1.3 ====> Installing kubectl client tool"
{
  mkdir -p /var/lib/kubelet /etc/kubernetes/pki /etc/kubernetes/manifests
  curl -kLO "https://dl.k8s.io/release/$KUBERNETES_VERSION/bin/linux/amd64/{kubeadm,kubectl,kubelet}"
  chmod +x kubectl kubeadm kubelet
  mv kubeadm kubectl kubelet /usr/local/bin/
}


### Step2 Certificates Generation

echo -e "\n" "Step2.1 ====> Generate Certificate Authority"
{
  # Create private key for CA
  openssl genrsa -out ca.key 2048

  # Create CSR using the private key
  openssl req -new -key ca.key -subj "/CN=KUBERNETES-CA/O=Kubernetes" -out ca.csr

  # Self sign the csr using its own private key
  openssl x509 -req -in ca.csr -signkey ca.key -CAcreateserial  -out ca.crt -days 1000
}

echo -e "\n" "Step2.2 ====> Generate Admin Certificate"
{
  # Generate private key for admin user
  openssl genrsa -out admin.key 2048

  # Generate CSR for admin user. Note the OU.
  openssl req -new -key admin.key -subj "/CN=admin/O=system:masters" -out admin.csr

  # Sign certificate for admin user using CA servers private
  openssl x509 -req -in admin.csr -CA ca.crt -CAkey ca.key -CAcreateserial  -out admin.crt -days 1000
}

echo -e "\n" "Step2.3 ====> Generate Controller Manager Certificate"
{
  # Generate private key for controller manager
  openssl genrsa -out kube-controller-manager.key 2048

  # Generate CSR for controller manager
  openssl req -new -key kube-controller-manager.key -subj "/CN=system:kube-controller-manager/O=system:kube-controller-manager" -out kube-controller-manager.csr

  # Sign certificate for controller manager using CA servers private key
  openssl x509 -req -in kube-controller-manager.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out kube-controller-manager.crt -days 1000
}

echo -e "\n" "Step2.4 ====> Generate Kube Proxy Certificate"
{
  # Generate private key for kube proxy
  openssl genrsa -out kube-proxy.key 2048

  # Generate CSR for kube proxy
  openssl req -new -key kube-proxy.key -subj "/CN=system:kube-proxy/O=system:node-proxier" -out kube-proxy.csr

  # Sign certificate for kube proxy using CA servers private key
  openssl x509 -req -in kube-proxy.csr -CA ca.crt -CAkey ca.key -CAcreateserial  -out kube-proxy.crt -days 1000
}

echo -e "\n" "Step2.5 ====> Generate Kube Scheduler Certificate"
{
  # Generate private key for kube scheduler
  openssl genrsa -out kube-scheduler.key 2048

  # Generate CSR for kube scheduler
  openssl req -new -key kube-scheduler.key -subj "/CN=system:kube-scheduler/O=system:kube-scheduler" -out kube-scheduler.csr

  # Sign certificate for kube scheduler using CA servers private key
  openssl x509 -req -in kube-scheduler.csr -CA ca.crt -CAkey ca.key -CAcreateserial  -out kube-scheduler.crt -days 1000
}

echo -e "\n" "Step2.6 ====> Generate Kube Apiserver Certificate"
{
cat > openssl.cnf <<EOF
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[v3_req]
basicConstraints = critical, CA:FALSE
keyUsage = critical, nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
DNS.1 = kubernetes
DNS.2 = kubernetes.default
DNS.3 = kubernetes.default.svc
DNS.4 = kubernetes.default.svc.cluster
DNS.5 = kubernetes.default.svc.cluster.local
IP.1 = ${API_SERVICE}
IP.2 = ${MASTER_1}
IP.4 = ${LOADBALANCER}
IP.5 = 127.0.0.1
EOF

  # Generate private key for kube apiserver
  openssl genrsa -out kube-apiserver.key 2048

  # Generate CSR for kube apiserver
  openssl req -new -key kube-apiserver.key -subj "/CN=kube-apiserver/O=Kubernetes" -out kube-apiserver.csr -config openssl.cnf

  # Sign certificate for kube apiserver using CA servers private key
  openssl x509 -req -in kube-apiserver.csr -CA ca.crt -CAkey ca.key -CAcreateserial  -out kube-apiserver.crt -extensions v3_req -extfile openssl.cnf -days 1000
}

echo -e "\n" "Step2.7 ====> Generate Kubelet Certificate for API"
{
cat > openssl-kubelet.cnf <<EOF
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[v3_req]
basicConstraints = critical, CA:FALSE
keyUsage = critical, nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
EOF

  # Generate private key for kubelet
  openssl genrsa -out apiserver-kubelet-client.key 2048

  # Generate CSR for kubelet
  openssl req -new -key apiserver-kubelet-client.key -subj "/CN=kube-apiserver-kubelet-client/O=system:masters" -out apiserver-kubelet-client.csr -config openssl-kubelet.cnf

  # Sign certificate for kubelet using CA servers private key
  openssl x509 -req -in apiserver-kubelet-client.csr -CA ca.crt -CAkey ca.key -CAcreateserial  -out apiserver-kubelet-client.crt -extensions v3_req -extfile openssl-kubelet.cnf -days 1000
}

echo -e "\n" "Step2.8 ====> Generate Kubelet Certificate for cluster nodes"
{
cat > openssl-worker.cnf <<EOF
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names
[alt_names]
DNS.1 = worker1
DNS.2 = worker2
DNS.3 = master
IP.1 = ${WORKER_1}
IP.2 = ${WORKER_2}
IP.3 = ${MASTER_1}
EOF

  for wrk in master worker1 worker2;
  do
    openssl genrsa -out $wrk.key 2048
    openssl req -new -key $wrk.key -subj "/CN=system:node:$wrk/O=system:nodes" -out $wrk.csr -config openssl-worker.cnf
    openssl x509 -req -in $wrk.csr -CA ca.crt -CAkey ca.key -CAcreateserial  -out $wrk.crt -extensions v3_req -extfile openssl-worker.cnf -days 1000
  done
}


echo -e "\n" "Step2.9 ====> Generate ETCD Server Certificate"
{
cat > openssl-etcd.cnf <<EOF
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names
[alt_names]
IP.1 = ${MASTER_1}
IP.3 = 127.0.0.1
EOF

  # Generate private key for etcd server
  openssl genrsa -out etcd-server.key 2048

  # Generate CSR for etcd server
  openssl req -new -key etcd-server.key -subj "/CN=etcd-server/O=Kubernetes" -out etcd-server.csr -config openssl-etcd.cnf

  # Sign certificate for etcd server using CA servers private key
  openssl x509 -req -in etcd-server.csr -CA ca.crt -CAkey ca.key -CAcreateserial  -out etcd-server.crt -extensions v3_req -extfile openssl-etcd.cnf -days 1000
}

echo -e "\n" "Step2.10 ====> Generate ServiceAccount Key Pair"
{
  # Generate private key for service account
  openssl genrsa -out service-account.key 2048

  # Generate CSR for service account
  openssl req -new -key service-account.key -subj "/CN=service-accounts/O=Kubernetes" -out service-account.csr

  # Sign certificate for service account using CA servers private key
  openssl x509 -req -in service-account.csr -CA ca.crt -CAkey ca.key -CAcreateserial  -out service-account.crt -days 1000
}

echo -e "\n" "Step2.11 ====> Distribute Certificates"
{
  for instance in master;
  do
    scp -o StrictHostKeyChecking=no *.crt *.key ${instance}:/etc/kubernetes/pki/
  done
  for instance in worker1 worker2;
  do
    scp -o StrictHostKeyChecking=no ca.crt $instance.crt $instance.key ${instance}:~/
  done
}


### Step3 Generate Kubernetes Configuration file

echo -e "\n" "Step3.1 ====> Generate kubeconfig file for kube-proxy service"
{
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=/etc/kubernetes/pki/ca.crt \
    --server=https://${LOADBALANCER}:6443 \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config set-credentials system:kube-proxy \
    --client-certificate=/etc/kubernetes/pki/kube-proxy.crt \
    --client-key=/etc/kubernetes/pki/kube-proxy.key \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:kube-proxy \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig
}

echo -e "\n" "Step3.2 ====> Generate kubeconfig file for kube-controller-manager service"
{
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=/etc/kubernetes/pki/ca.crt \
    --server=https://127.0.0.1:6443 \
    --kubeconfig=kube-controller-manager.kubeconfig

  kubectl config set-credentials system:kube-controller-manager \
    --client-certificate=/etc/kubernetes/pki/kube-controller-manager.crt \
    --client-key=/etc/kubernetes/pki/kube-controller-manager.key \
    --kubeconfig=kube-controller-manager.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:kube-controller-manager \
    --kubeconfig=kube-controller-manager.kubeconfig

  kubectl config use-context default --kubeconfig=kube-controller-manager.kubeconfig
}

echo -e "\n" "Step3.3 ====> Generate kubeconfig file for kube-scheduler service"
{
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=/etc/kubernetes/pki/ca.crt \
    --server=https://127.0.0.1:6443 \
    --kubeconfig=kube-scheduler.kubeconfig

  kubectl config set-credentials system:kube-scheduler \
    --client-certificate=/etc/kubernetes/pki/kube-scheduler.crt \
    --client-key=/etc/kubernetes/pki/kube-scheduler.key \
    --kubeconfig=kube-scheduler.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:kube-scheduler \
    --kubeconfig=kube-scheduler.kubeconfig

  kubectl config use-context default --kubeconfig=kube-scheduler.kubeconfig
}

echo -e "\n" "Step3.4 ====> Generate kubeconfig file for admin user"
{
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.crt \
    --embed-certs=true \
    --server=https://127.0.0.1:6443 \
    --kubeconfig=admin.kubeconfig

  kubectl config set-credentials admin \
    --client-certificate=admin.crt \
    --client-key=admin.key \
    --embed-certs=true \
    --kubeconfig=admin.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=admin \
    --kubeconfig=admin.kubeconfig

  kubectl config use-context default --kubeconfig=admin.kubeconfig
}

echo -e "\n" "Step3.5 ====> Generate kubeconfig file for kubelet"
{
  for wrk in master worker1 worker2;
  do
    kubectl config set-cluster kubernetes-the-hard-way \
        --certificate-authority=/etc/kubernetes/pki/ca.crt \
        --server=https://${LOADBALANCER}:6443 \
        --kubeconfig=$wrk.kubeconfig

    kubectl config set-credentials system:node:$wrk \
        --client-certificate=/etc/kubernetes/pki/$wrk.crt \
        --client-key=/etc/kubernetes/pki/$wrk.key \
        --kubeconfig=$wrk.kubeconfig

    kubectl config set-context default \
        --cluster=kubernetes-the-hard-way \
        --user=system:node:$wrk \
        --kubeconfig=$wrk.kubeconfig

    kubectl config use-context default --kubeconfig=$wrk.kubeconfig
  done
}

echo -e "\n" "Step3.6 ====> Distribute kubeconfig files"
{
  for instance in worker1 worker2;
  do
    scp -o StrictHostKeyChecking=no $instance.kubeconfig ${instance}:~/
  done
  cp admin.kubeconfig /etc/kubernetes/admin.conf
  cp kube-controller-manager.kubeconfig /etc/kubernetes/controller-manager.conf
  cp kube-scheduler.kubeconfig /etc/kubernetes/scheduler.conf
}


### Step4 Generating Data Encryption Config and Key

echo -e "\n" "Step4.1 ====> Generate an encryption key"
{
  ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)
}

echo -e "\n" "Step4.2 ====> Create Encryption Config file"
{
cat > encryption-config.yaml <<EOF
kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENCRYPTION_KEY}
      - identity: {}
EOF
}

echo -e "\n" "Step4.3 ====> Distribute Encryption config file"
{
  cp encryption-config.yaml /etc/kubernetes/pki
}


### Step5 Bootstrapping ETCD Server

echo -e "\n" "Step5.1 ====> Download and Install the etcd Binaries"
{
  wget --no-check-certificate "https://github.com/coreos/etcd/releases/download/${ETCD_VERSION}/etcd-${ETCD_VERSION}-linux-amd64.tar.gz"
  tar -xvf etcd-${ETCD_VERSION}-linux-amd64.tar.gz
  mv etcd-${ETCD_VERSION}-linux-amd64/etcd* /usr/local/bin/
}


echo -e "\n" "Step5.2 ====> Configure ETCD Server"
{
  mkdir -p /etc/etcd /var/lib/etcd
  cp etcd-server.key etcd-server.crt /etc/etcd/
  chown root:root /etc/etcd/*
  chmod 600 /etc/etcd/*
  ln -s /etc/kubernetes/pki/ca.crt /etc/etcd/ca.crt
  ln -s /etc/kubernetes/pki/ca.key /etc/etcd/ca.key

cat <<EOF | sudo tee /etc/systemd/system/etcd.service
[Unit]
Description=etcd
Documentation=https://github.com/coreos

[Service]
ExecStart=/usr/local/bin/etcd \\
  --name ${ETCD_NAME} \\
  --cert-file=/etc/etcd/etcd-server.crt \\
  --key-file=/etc/etcd/etcd-server.key \\
  --peer-cert-file=/etc/etcd/etcd-server.crt \\
  --peer-key-file=/etc/etcd/etcd-server.key \\
  --trusted-ca-file=/etc/etcd/ca.crt \\
  --peer-trusted-ca-file=/etc/etcd/ca.crt \\
  --peer-client-cert-auth \\
  --client-cert-auth \\
  --initial-advertise-peer-urls https://${INTERNAL_IP}:2380 \\
  --listen-peer-urls https://${INTERNAL_IP}:2380 \\
  --listen-client-urls https://${INTERNAL_IP}:2379,https://127.0.0.1:2379 \\
  --advertise-client-urls https://${INTERNAL_IP}:2379 \\
  --initial-cluster-token etcd-cluster-0 \\
  --initial-cluster master=https://${MASTER_1}:2380\\
  --initial-cluster-state new \\
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
}

echo -e "\n" "Step5.3 ====> Start ETCD Server"
{
  systemctl daemon-reload && { systemctl enable etcd;systemctl start etcd; }
  systemctl status etcd|grep 'Active: active' && echo -e "\n" "ETCD Server is Active"
}


### Step6 Bootstrapping Kubernetes Control Plane

echo -e "\n" "Step6.1 ====> Configure kubelet"
{
  mv ${HOSTNAME}.kubeconfig /var/lib/kubelet/kubelet.kubeconfig
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
staticPodPath: /etc/kubernetes/manifests
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
}


echo -e "\n" "Step6.2 ====> Configure Kube-APIServer"
{

cat >/etc/kubernetes/manifests/kube-apiserver.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  annotations:
    kubeadm.kubernetes.io/kube-apiserver.advertise-address.endpoint: ${MASTER_1}:6443
  labels:
    component: kube-apiserver
    tier: control-plane
  name: kube-apiserver
  namespace: kube-system
spec:
  containers:
  - command:
    - kube-apiserver
    - --advertise-address=${INTERNAL_IP}
    - --allow-privileged=true
    - --apiserver-count=2
    - --audit-log-maxage=30
    - --audit-log-maxbackup=3
    - --audit-log-maxsize=100
    - --audit-log-path=/var/log/audit.log
    - --authorization-mode=Node,RBAC
    - --bind-address=0.0.0.0
    - --client-ca-file=/etc/kubernetes/pki/ca.crt
    - --enable-admission-plugins=NodeRestriction,ServiceAccount
    - --enable-bootstrap-token-auth=true
    - --etcd-cafile=/etc/kubernetes/pki/ca.crt
    - --etcd-certfile=/etc/kubernetes/pki/etcd-server.crt
    - --etcd-keyfile=/etc/kubernetes/pki/etcd-server.key
    - --etcd-servers=https://${MASTER_1}:2379
    - --event-ttl=1h
    - --encryption-provider-config=/etc/kubernetes/pki/encryption-config.yaml
    - --kubelet-certificate-authority=/etc/kubernetes/pki/ca.crt
    - --kubelet-client-certificate=/etc/kubernetes/pki/apiserver-kubelet-client.crt
    - --kubelet-client-key=/etc/kubernetes/pki/apiserver-kubelet-client.key
    - --runtime-config=api/all=true
    - --service-account-key-file=/etc/kubernetes/pki/service-account.crt
    - --service-account-signing-key-file=/etc/kubernetes/pki/service-account.key
    - --service-account-issuer=https://${LOADBALANCER}:6443
    - --service-cluster-ip-range=${SERVICE_CIDR}
    - --service-node-port-range=30000-32767
    - --tls-cert-file=/etc/kubernetes/pki/kube-apiserver.crt
    - --tls-private-key-file=/etc/kubernetes/pki/kube-apiserver.key
    - --v=2
    image: k8s.gcr.io/kube-apiserver:${KUBERNETES_VERSION}
    imagePullPolicy: IfNotPresent
    livenessProbe:
      failureThreshold: 8
      httpGet:
        host: ${MASTER_1}
        path: /livez
        port: 6443
        scheme: HTTPS
      initialDelaySeconds: 10
      periodSeconds: 10
      timeoutSeconds: 15
    name: kube-apiserver
    readinessProbe:
      failureThreshold: 3
      httpGet:
        host: ${MASTER_1}
        path: /readyz
        port: 6443
        scheme: HTTPS
      periodSeconds: 1
      timeoutSeconds: 15
    resources:
      requests:
        cpu: 250m
    startupProbe:
      failureThreshold: 24
      httpGet:
        host: ${MASTER_1}
        path: /livez
        port: 6443
        scheme: HTTPS
      initialDelaySeconds: 10
      periodSeconds: 10
      timeoutSeconds: 15
    volumeMounts:
    - mountPath: /etc/ssl/certs
      name: ca-certs
      readOnly: true
    - mountPath: /etc/pki
      name: etc-pki
      readOnly: true
    - mountPath: /etc/kubernetes/pki
      name: k8s-certs
      readOnly: true
  hostNetwork: true
  priorityClassName: system-node-critical
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  volumes:
  - hostPath:
      path: /etc/ssl/certs
      type: DirectoryOrCreate
    name: ca-certs
  - hostPath:
      path: /etc/pki
      type: DirectoryOrCreate
    name: etc-pki
  - hostPath:
      path: /etc/kubernetes/pki
      type: DirectoryOrCreate
    name: k8s-certs
EOF
}

echo -e "\n" "Step6.3 ====> Configure Kube Controller Manager"
{

cat >/etc/kubernetes/manifests/kube-controller-manager.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  labels:
    component: kube-controller-manager
    tier: control-plane
  name: kube-controller-manager
  namespace: kube-system
spec:
  containers:
  - command:
    - kube-controller-manager
    - --allocate-node-cidrs=true
    - --authentication-kubeconfig=/etc/kubernetes/controller-manager.conf
    - --authorization-kubeconfig=/etc/kubernetes/controller-manager.conf
    - --bind-address=127.0.0.1
    - --client-ca-file=/etc/kubernetes/pki/ca.crt
    - --cluster-cidr=${POD_CIDR}
    - --cluster-name=kubernetes
    - --cluster-signing-cert-file=/etc/kubernetes/pki/ca.crt
    - --cluster-signing-key-file=/etc/kubernetes/pki/ca.key
    - --controllers=*,bootstrapsigner,tokencleaner
    - --kubeconfig=/etc/kubernetes/controller-manager.conf
    - --leader-elect=true
    - --node-cidr-mask-size=24
    - --requestheader-client-ca-file=/etc/kubernetes/pki/ca.crt
    - --root-ca-file=/etc/kubernetes/pki/ca.crt
    - --service-account-private-key-file=/etc/kubernetes/pki/service-account.key
    - --service-cluster-ip-range=${SERVICE_CIDR}
    - --use-service-account-credentials=true
    - --v=2
    image: k8s.gcr.io/kube-controller-manager:${KUBERNETES_VERSION}
    imagePullPolicy: IfNotPresent
    livenessProbe:
      failureThreshold: 8
      httpGet:
        host: 127.0.0.1
        path: /healthz
        port: 10257
        scheme: HTTPS
      initialDelaySeconds: 10
      periodSeconds: 10
      timeoutSeconds: 15
    name: kube-controller-manager
    resources:
      requests:
        cpu: 200m
    startupProbe:
      failureThreshold: 24
      httpGet:
        host: 127.0.0.1
        path: /healthz
        port: 10257
        scheme: HTTPS
      initialDelaySeconds: 10
      periodSeconds: 10
      timeoutSeconds: 15
    volumeMounts:
    - mountPath: /etc/ssl/certs
      name: ca-certs
      readOnly: true
    - mountPath: /etc/pki
      name: etc-pki
      readOnly: true
    - mountPath: /usr/libexec/kubernetes/kubelet-plugins/volume/exec
      name: flexvolume-dir
    - mountPath: /etc/kubernetes/pki
      name: k8s-certs
      readOnly: true
    - mountPath: /etc/kubernetes/controller-manager.conf
      name: kubeconfig
      readOnly: true
  hostNetwork: true
  priorityClassName: system-node-critical
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  volumes:
  - hostPath:
      path: /etc/ssl/certs
      type: DirectoryOrCreate
    name: ca-certs
  - hostPath:
      path: /etc/pki
      type: DirectoryOrCreate
    name: etc-pki
  - hostPath:
      path: /usr/libexec/kubernetes/kubelet-plugins/volume/exec
      type: DirectoryOrCreate
    name: flexvolume-dir
  - hostPath:
      path: /etc/kubernetes/pki
      type: DirectoryOrCreate
    name: k8s-certs
  - hostPath:
      path: /etc/kubernetes/controller-manager.conf
      type: FileOrCreate
    name: kubeconfig
EOF
}

echo -e "\n" "Step6.3 ====> Configure Kube Scheduler"
{

cat >/etc/kubernetes/manifests/kube-scheduler.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  labels:
    component: kube-scheduler
    tier: control-plane
  name: kube-scheduler
  namespace: kube-system
spec:
  containers:
  - command:
    - kube-scheduler
    - --authentication-kubeconfig=/etc/kubernetes/scheduler.conf
    - --authorization-kubeconfig=/etc/kubernetes/scheduler.conf
    - --bind-address=127.0.0.1
    - --kubeconfig=/etc/kubernetes/scheduler.conf
    - --leader-elect=true
    - --v=2
    image: k8s.gcr.io/kube-scheduler:${KUBERNETES_VERSION}
    imagePullPolicy: IfNotPresent
    livenessProbe:
      failureThreshold: 8
      httpGet:
        host: 127.0.0.1
        path: /healthz
        port: 10259
        scheme: HTTPS
      initialDelaySeconds: 10
      periodSeconds: 10
      timeoutSeconds: 15
    name: kube-scheduler
    resources:
      requests:
        cpu: 100m
    startupProbe:
      failureThreshold: 24
      httpGet:
        host: 127.0.0.1
        path: /healthz
        port: 10259
        scheme: HTTPS
      initialDelaySeconds: 10
      periodSeconds: 10
      timeoutSeconds: 15
    volumeMounts:
    - mountPath: /etc/kubernetes/scheduler.conf
      name: kubeconfig
      readOnly: true
    - mountPath: /etc/kubernetes/pki
      name: k8s-certs
      readOnly: true
  hostNetwork: true
  priorityClassName: system-node-critical
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  volumes:
  - hostPath:
      path: /etc/kubernetes/scheduler.conf
      type: FileOrCreate
    name: kubeconfig
  - hostPath:
      path: /etc/kubernetes/pki
      type: DirectoryOrCreate
    name: k8s-certs
EOF
  chmod 600 /etc/kubernetes/*.conf
}


echo -e "\n" "Step6.4 ====> Start Controller Services"
{
  systemctl daemon-reload && { systemctl enable kubelet;systemctl start kubelet; }
  until netstat -ntlp|grep LISTEN|grep 6443; do  echo "Waiting for APIServer to be up....";sleep 10;done
  test ! -d $HOME/.kube && mkdir $HOME/.kube
  cp /etc/kubernetes/admin.conf $HOME/.kube/config
  kubectl get cs
}

echo -e "\n" "Step6.5 ====> Verification of Kubernetes Version"
{
  kubectl cluster-info
}


### Step7 Pod Network Provisioning

echo -e "\n" "Step7.1 ====> Deploy Flannel Network"
{
  wget --no-check-certificate https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
  kubectl apply -f kube-flannel.yml
}


### Step8 Deploy Add-ons

echo -e "\n" "Step8.1 ====> Deploy Kube-proxy"
{
  mkdir kube-proxy-cm kube-proxy-secrets
  cp kube-proxy.kubeconfig kube-proxy-cm/kubeconfig.conf
  cp ca.crt kube-proxy.crt kube-proxy.key kube-proxy-secrets

cat >kube-proxy-cm/config.conf <<EOF
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
clientConnection:
  kubeconfig: /var/lib/kube-proxy/kubeconfig.conf
mode: ipvs
clusterCIDR: ${POD_CIDR}
EOF

  kubectl create cm kube-proxy --from-file=./kube-proxy-cm -n kube-system --dry-run=client -oyaml >kube-proxy-cm.yaml
  kubectl create secret generic kube-proxy --from-file=./kube-proxy-secrets -n kube-system --dry-run=client -oyaml >kube-proxy-secret.yaml
  kubectl apply -f $DIR/kube-proxy-cm.yaml
  kubectl apply -f $DIR/kube-proxy-secret.yaml
  envsubst < $HOME/kube-proxy.yaml|kubectl apply -f -
}

echo -e "\n" "Step8.2 ====> Deploy CoreDNS"
{
  envsubst < $HOME/coredns.yaml|kubectl apply -f -
}
