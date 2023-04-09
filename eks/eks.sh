#!/bin/bash

function eks_verify_tools_installed() {

   if ! [ -x "$(command -v kubectl)" ]; then
      echo "kubectl is not installed"
      echo "Please install kubectl and try again."
      echo "Link: https://kubernetes.io/docs/tasks/tools/install-kubectl/"
      exit 1
   fi

   if ! [ -x "$(command -v helm)" ]; then
      echo "helm is not installed"
      echo "Installing helm and try again."
      echo "Link: https://helm.sh/docs/intro/install"
      curl -s https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 |sudo bash
   fi

   if ! [ -x "$(command -v eksctl)" ]; then
      echo "eksctl is not installed"
      echo "Please install eksctl and try again."
      echo "Link: https://docs.aws.amazon.com/eks/latest/userguide/eksctl.html"
      curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | sudo tar xz -C /usr/bin
   fi
}

function eks_configure_kubeconfig() {
   aws eks --region ${AWS_REGION} update-kubeconfig --name ${CLUSTER_NAME}
}

