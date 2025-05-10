#! /bin/bash
#### Script to build kubernetes cluster"
#set -e
export LOGS=/root/install_config.log
## Script usage
if [ $# -ne 1 ]
then
echo -e "\n" "Usage: $0 1.x.x";
echo -e "\n" "example: $0 1.28.0";
fi

## Cluster node Installation
cd /root
echo -e "\n" "Cluster node Installation for master & worker nodes in-progress"
echo -e "\n" "Cluster node installation in master node" >>$LOGS 2>&1
bash cluster_install.sh $1 >>$LOGS 2>&1
echo -e "\n" "Cluster node installation in worker1 node" >>$LOGS 2>&1
ssh worker1 bash -s <./cluster_install.sh $1 >>$LOGS 2>&1
echo -e "\n" "Cluster node installation in worker2 node" >>$LOGS 2>&1
ssh worker2 bash -s <./cluster_install.sh $1 >>$LOGS 2>&1
echo -e "\n" "Cluster node Installation completed for master & worker nodes"

## Cluster configuration
echo -e "\n" "Cluster configuration in-progress"
echo -e "\n" "Cluster configuration in master node" >>$LOGS 2>&1
bash cluster_config.sh $1 >>$LOGS 2>&1
CLUSTER_CONFIG=$(kubeadm token create --print-join-command)
echo -e "\n" "worker node worker1 joining cluster" >>$LOGS 2>&1
ssh worker1 "$CLUSTER_CONFIG" >>$LOGS 2>&1
echo -e "\n" "worker node worker2 joining cluster" >>$LOGS 2>&1
ssh worker2 "$CLUSTER_CONFIG" >>$LOGS 2>&1
for i in worker1 worker2
do
kubectl wait --for=condition=Ready node $i >>$LOGS 2>&1;
kubectl label node $i node-role.kubernetes.io/worker="" >>$LOGS 2>&1;
done
echo -e "\n" "Cluster configuration completed in master & worker nodes"
kubectl get node

## Ingress controller deployment
echo -e "\n" "Ingress controller deployment in-progress"
echo -e "\n" "Ingress controller deployment" >>$LOGS 2>&1;
bash deploy_ingress.sh >>$LOGS 2>&1;
echo -e "\n" "Ingress controller deployed in cluster"
echo -e "\n" "Sample application has been deployed , Can be accessed through http://app.groofy.help"