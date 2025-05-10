#! /bin/bash
#### Script to build kubernetes cluster"
set -e

## Script usage
if [ $# -ne 1 ]
then
echo -e "\n" "Usage: $0 1.x.x";
echo -e "\n" "example: $0 1.28.0";
fi

## Cluster node Installation
cd /root
echo -e "\n" "Cluster node installation in master node" >>/root/install.log 2>&1
bash cluster_install.sh $1 >>/root/install.log 2>&1
echo -e "\n" "Cluster node installation in worker1 node" >>/root/install.log 2>&1
ssh worker1 bash -s <./cluster_install.sh $1 >>/root/install.log 2>&1
echo -e "\n" "Cluster node installation in worker2 node" >>/root/install.log 2>&1
ssh worker2 bash -s <./cluster_install.sh $1 >>/root/install.log 2>&1
echo -e "\n" "Cluster node Installation completed for master & worker nodes"

## Cluster configuration
bash cluster_config.sh $1 >>/root/config.log
CLUSTER_CONFIG=$(kubeadm token create --print-join-command)
ssh worker1 "$CLUSTER_CONFIG" >>/root/config.log
ssh worker2 "$CLUSTER_CONFIG" >>/root/config.log
for i in worker1 worker2
do
kubectl wait --for=condition=Ready node $i;
kubectl label node $i node-role.kubernetes.io/worker="";
done
kubectl get node
echo -e "\n" "Cluster configuration completed in master & worker nodes"

## Ingress controller deployment
bash deploy_ingress.sh
echo -e "\n" "Ingress controller deployed in cluster"
echo -e "\n" "Sample application has been deployed , Can be accessed through http://app.groofy.help"