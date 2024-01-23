#! /bin/bash
##################################################################################################
##### Description: Script to configure master Nodes to setup kubernetes cluster              #####
##### Usage: ./configure-master.sh                                                           #####
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

### Step1 Client tool Installation
echo -e "\n" "Step1 ====> Installing kubectl client tool in master nodes"
{
  curl -sLO "https://dl.k8s.io/release/$KUBE_VERSION/bin/linux/amd64/kubectl"
  chmod +x kubectl
  mv kubectl /usr/local/bin/
  mkdir /root/certs
  cd /root/certs
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

echo -e "\n" "Step2.7 ====> Generate Kubelet Certificate"
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

echo -e "\n" "Step2.8 ====> Generate ETCD Server Certificate"
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

echo -e "\n" "Step2.9 ====> Generate ServiceAccount Key Pair"
{
  # Generate private key for service account
  openssl genrsa -out service-account.key 2048

  # Generate CSR for service account
  openssl req -new -key service-account.key -subj "/CN=service-accounts/O=Kubernetes" -out service-account.csr

  # Sign certificate for service account using CA servers private key
  openssl x509 -req -in service-account.csr -CA ca.crt -CAkey ca.key -CAcreateserial  -out service-account.crt -days 1000
}
  
echo -e "\n" "Step2.10 ====> Distribute Certificates"
{
  for instance in master1; 
  do
    scp -o StrictHostKeyChecking=no ca.crt ca.key kube-apiserver.key kube-apiserver.crt \
       apiserver-kubelet-client.crt apiserver-kubelet-client.key service-account.key service-account.crt \
       etcd-server.key etcd-server.crt kube-controller-manager.key kube-controller-manager.crt \
       kube-scheduler.key kube-scheduler.crt ${instance}:~/
  done
  for instance in worker1 worker2; 
  do
    scp ca.crt kube-proxy.crt kube-proxy.key ${instance}:~/
  done
}

### Step3 Generate Kubernetes Configuration file
echo -e "\n" "Step3.1 ====> Generate kubeconfig file for kube-proxy service"
{
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=/var/lib/kubernetes/pki/ca.crt \
    --server=https://${LOADBALANCER}:6443 \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config set-credentials system:kube-proxy \
    --client-certificate=/var/lib/kubernetes/pki/kube-proxy.crt \
    --client-key=/var/lib/kubernetes/pki/kube-proxy.key \
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
    --certificate-authority=/var/lib/kubernetes/pki/ca.crt \
    --server=https://127.0.0.1:6443 \
    --kubeconfig=kube-controller-manager.kubeconfig

  kubectl config set-credentials system:kube-controller-manager \
    --client-certificate=/var/lib/kubernetes/pki/kube-controller-manager.crt \
    --client-key=/var/lib/kubernetes/pki/kube-controller-manager.key \
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
    --certificate-authority=/var/lib/kubernetes/pki/ca.crt \
    --server=https://127.0.0.1:6443 \
    --kubeconfig=kube-scheduler.kubeconfig

  kubectl config set-credentials system:kube-scheduler \
    --client-certificate=/var/lib/kubernetes/pki/kube-scheduler.crt \
    --client-key=/var/lib/kubernetes/pki/kube-scheduler.key \
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

echo -e "\n" "Step3.5 ====> Distribute kubeconfig files"
{
  for instance in worker1 worker2; 
  do
    scp kube-proxy.kubeconfig ${instance}:~/
  done
  for instance in master1; 
  do
    scp admin.kubeconfig kube-controller-manager.kubeconfig kube-scheduler.kubeconfig ${instance}:~/
  done
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
  for instance in master1; 
  do
    scp encryption-config.yaml ${instance}:~/
  done
  for instance in master1; do
    ssh ${instance} mkdir -p /var/lib/kubernetes/
    ssh ${instance} mv encryption-config.yaml /var/lib/kubernetes/
  done
}


### Step5 Bootstrapping ETCD Server
echo -e "\n" "Step5.1 ====> Download and Install the etcd Binaries"
{
  ETCD_VERSION="v3.5.9"
  wget -q "https://github.com/coreos/etcd/releases/download/${ETCD_VERSION}/etcd-${ETCD_VERSION}-linux-amd64.tar.gz"
  tar -xvf etcd-${ETCD_VERSION}-linux-amd64.tar.gz
  mv etcd-${ETCD_VERSION}-linux-amd64/etcd* /usr/local/bin/
}


echo -e "\n" "Step5.2 ====> Configure ETCD Server"
{
  mkdir -p /etc/etcd /var/lib/etcd /var/lib/kubernetes/pki
  cp etcd-server.key etcd-server.crt /etc/etcd/
  cp ca.crt /var/lib/kubernetes/pki/
  chown root:root /etc/etcd/*
  chmod 600 /etc/etcd/*
  chown root:root /var/lib/kubernetes/pki/*
  chmod 600 /var/lib/kubernetes/pki/*
  ln -s /var/lib/kubernetes/pki/ca.crt /etc/etcd/ca.crt
  
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
  --initial-cluster master1=https://${MASTER_1}:2380\\
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
  systemctl daemon-reload
  systemctl enable etcd
  systemctl start etcd
}


### Step6 Bootstrapping Kubernetes Control Plane
echo -e "\n" "Step6.1 ====> Download and Install Kubernetes Controller Binaries"
{
  wget -q "https://dl.k8s.io/release/${KUBE_VERSION}/bin/linux/amd64/kube-apiserver" \
    "https://dl.k8s.io/release/${KUBE_VERSION}/bin/linux/amd64/kube-controller-manager" \
    "https://dl.k8s.io/release/${KUBE_VERSION}/bin/linux/amd64/kube-scheduler" \
    "https://dl.k8s.io/release/${KUBE_VERSION}/bin/linux/amd64/kubectl"
  chmod +x kube-apiserver kube-controller-manager kube-scheduler kubectl
  mv kube-apiserver kube-controller-manager kube-scheduler kubectl /usr/local/bin/
}
  
echo -e "\n" "Step6.1 ====> Configure Kube API Server"
{
  mkdir -p /var/lib/kubernetes/pki
  # Only copy CA keys as we'll need them again for workers.
  cp ca.crt ca.key /var/lib/kubernetes/pki
  for c in kube-apiserver service-account apiserver-kubelet-client etcd-server kube-scheduler kube-controller-manager
  do
    mv "$c.crt" "$c.key" /var/lib/kubernetes/pki/
  done
  chown root:root /var/lib/kubernetes/pki/*
  chmod 600 /var/lib/kubernetes/pki/*

cat <<EOF | sudo tee /etc/systemd/system/kube-apiserver.service
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-apiserver \\
  --advertise-address=${INTERNAL_IP} \\
  --allow-privileged=true \\
  --apiserver-count=2 \\
  --audit-log-maxage=30 \\
  --audit-log-maxbackup=3 \\
  --audit-log-maxsize=100 \\
  --audit-log-path=/var/log/audit.log \\
  --authorization-mode=Node,RBAC \\
  --bind-address=0.0.0.0 \\
  --client-ca-file=/var/lib/kubernetes/pki/ca.crt \\
  --enable-admission-plugins=NodeRestriction,ServiceAccount \\
  --enable-bootstrap-token-auth=true \\
  --etcd-cafile=/var/lib/kubernetes/pki/ca.crt \\
  --etcd-certfile=/var/lib/kubernetes/pki/etcd-server.crt \\
  --etcd-keyfile=/var/lib/kubernetes/pki/etcd-server.key \\
  --etcd-servers=https://${MASTER_1}:2379,https://${MASTER_2}:2379 \\
  --event-ttl=1h \\
  --encryption-provider-config=/var/lib/kubernetes/encryption-config.yaml \\
  --kubelet-certificate-authority=/var/lib/kubernetes/pki/ca.crt \\
  --kubelet-client-certificate=/var/lib/kubernetes/pki/apiserver-kubelet-client.crt \\
  --kubelet-client-key=/var/lib/kubernetes/pki/apiserver-kubelet-client.key \\
  --runtime-config=api/all=true \\
  --service-account-key-file=/var/lib/kubernetes/pki/service-account.crt \\
  --service-account-signing-key-file=/var/lib/kubernetes/pki/service-account.key \\
  --service-account-issuer=https://${LOADBALANCER}:6443 \\
  --service-cluster-ip-range=${SERVICE_CIDR} \\
  --service-node-port-range=30000-32767 \\
  --tls-cert-file=/var/lib/kubernetes/pki/kube-apiserver.crt \\
  --tls-private-key-file=/var/lib/kubernetes/pki/kube-apiserver.key \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
}

echo -e "\n" "Step6.2 ====> Configure Kube Controller Manager"
{
  mv kube-controller-manager.kubeconfig /var/lib/kubernetes/

cat <<EOF | sudo tee /etc/systemd/system/kube-controller-manager.service
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \\
  --allocate-node-cidrs=true \\
  --authentication-kubeconfig=/var/lib/kubernetes/kube-controller-manager.kubeconfig \\
  --authorization-kubeconfig=/var/lib/kubernetes/kube-controller-manager.kubeconfig \\
  --bind-address=127.0.0.1 \\
  --client-ca-file=/var/lib/kubernetes/pki/ca.crt \\
  --cluster-cidr=${POD_CIDR} \\
  --cluster-name=kubernetes \\
  --cluster-signing-cert-file=/var/lib/kubernetes/pki/ca.crt \\
  --cluster-signing-key-file=/var/lib/kubernetes/pki/ca.key \\
  --controllers=*,bootstrapsigner,tokencleaner \\
  --kubeconfig=/var/lib/kubernetes/kube-controller-manager.kubeconfig \\
  --leader-elect=true \\
  --node-cidr-mask-size=24 \\
  --requestheader-client-ca-file=/var/lib/kubernetes/pki/ca.crt \\
  --root-ca-file=/var/lib/kubernetes/pki/ca.crt \\
  --service-account-private-key-file=/var/lib/kubernetes/pki/service-account.key \\
  --service-cluster-ip-range=${SERVICE_CIDR} \\
  --use-service-account-credentials=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
}

echo -e "\n" "Step6.3 ====> Configure Kube Scheduler"
{
  mv kube-scheduler.kubeconfig /var/lib/kubernetes/

cat <<EOF | sudo tee /etc/systemd/system/kube-scheduler.service
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-scheduler \\
  --kubeconfig=/var/lib/kubernetes/kube-scheduler.kubeconfig \\
  --leader-elect=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  chmod 600 /var/lib/kubernetes/*.kubeconfig
}

echo -e "\n" "Step6.4 ====> Start Controller Services"
{
  sudo systemctl daemon-reload
  sudo systemctl enable kube-apiserver kube-controller-manager kube-scheduler
  sudo systemctl start kube-apiserver kube-controller-manager kube-scheduler
  kubectl get componentstatuses --kubeconfig admin.kubeconfig
}

echo -e "\n" "Step6.5 ====> Verification of Kubernetes Version"
{
  curl  https://${LOADBALANCER}:6443/version -k
}


### Step7 Generate Kubelet Certificates
echo -e "\n" "Step7.1 ====> Generate Kubelet Certificate"
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
IP.1 = ${WORKER_1}
IP.2 = ${WORKER_2}
EOF

  for wrk in worker1 worker2;
  do
    openssl genrsa -out $wrk.key 2048
    openssl req -new -key $wrk.key -subj "/CN=system:node:$wrk/O=system:nodes" -out $wrk.csr -config openssl-$wrk.cnf
    openssl x509 -req -in $wrk.csr -CA ca.crt -CAkey ca.key -CAcreateserial  -out $wrk.crt -extensions v3_req -extfile openssl-worker.cnf -days 1000
  
    kubectl config set-cluster kubernetes-the-hard-way \
        --certificate-authority=/var/lib/kubernetes/pki/ca.crt \
        --server=https://${LOADBALANCER}:6443 \
        --kubeconfig=$wrk.kubeconfig
    
    kubectl config set-credentials system:node:worker-1 \
        --client-certificate=/var/lib/kubernetes/pki/worker-1.crt \
        --client-key=/var/lib/kubernetes/pki/worker-1.key \
        --kubeconfig=$wrk.kubeconfig
    
    kubectl config set-context default \
        --cluster=kubernetes-the-hard-way \
        --user=system:node:worker-1 \
        --kubeconfig=$wrk.kubeconfig
    
    kubectl config use-context default --kubeconfig=$wrk.kubeconfig
    scp ca.crt $wrk.crt $wrk.kubeconfig  $wrk:~/
  done
}


### Step8 Pod Network Provisioning
echo -e "\n" "Step8.1 ====> Deploy Flannel Network"
{
  mkdir /root/.kube && cp admin.kubeconfig /root/.kube/config
  kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
}

echo -e "\n" "Step8.2 ====> Verification of Flannel pods"
{
  kubectl get pod -A
}


### Step9 Deploy DNS Add-on
echo -e "\n" "Step9.1 ====> Deploy CoreDNS"
{
  kubectl apply -f https://raw.githubusercontent.com/mmumshad/kubernetes-the-hard-way/master/deployments/coredns.yaml
  kubectl get pods -l k8s-app=kube-dns -n kube-system
}
