#!/bin/bash

function version() {
  echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }';
}

function eks_verify_tools_installed() {
  AWSCLI_VERSION=$(aws --version | cut -d" " -f1 | cut -d"/" -f2)
  if [ $(version $AWSCLI_VERSION) -lt $(version "1.16.156") ]; then
      echo "awscli installed version $AWSCLI_VERSION is older than required version 1.16.156"
      echo "Please run AWS@Apple setup again to ugrade."
      echo "Link: https://github.pie.apple.com/CloudTech/aws-apple/tree/main/setup"
      exit 1
  fi

  if ! [ -x "$(command -v kubectl)" ]; then
    echo "kubectl is not installed"
    echo "Please install kubectl and try again."
    echo "Link: https://kubernetes.io/docs/tasks/tools/install-kubectl/"
    exit 1
  fi

  if ! [ -x "$(command -v helm)" ]; then
    echo "helm is not installed"
    echo "Please install helm and try again."
    echo "Link: https://helm.sh/docs/intro/install"
    exit 1
  fi
}

function eks_configure_kubeconfig() {
  aws eks --region ${AWS_REGION} update-kubeconfig --name ${CLUSTER_NAME}
}

