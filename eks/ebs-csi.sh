#!/bin/bash

##################################################################################################################
####                  Description: Script to deploy Amazon EKS EBS CSI Driver                                 ####
####                                           								      ####
##################################################################################################################

set -ex

#### Install EBS CSI Driver
eksctl utils associate-iam-oidc-provider --cluster $CLUSTER_NAME --approve
curl -o ebs-iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-ebs-csi-driver/v0.9.0/docs/example-iam-policy.json
aws iam create-policy --policy-name ${CLUSTER_NAME}_EKS_EBS_Policy --policy-document file://ebs-iam-policy.json
OIDCID=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text|sed 's|https://||g'|awk -F'/' '{print $3}')
ACCID=$(aws sts get-caller-identity --query "Account" --output text)
REGION=$AWS_REGION || REGION=$AWS_DEFAULT_REGION
export OIDCID ACCID REGION 
cat > trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
         "Federated": "arn:aws:iam::$ACCID:oidc-provider/oidc.eks.$REGION.amazonaws.com/id/$OIDCID"
       },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.$REGION.amazonaws.com/id/$OIDCID:sub": "system:serviceaccount:ebs-csi:ebs-csi-controller-sa"
         }
       }
    }
  ]
}

EOF

aws iam create-role --role-name ${CLUSTER_NAME}_EKS_EBS_role --assume-role-policy-document file://"trust-policy.json"
aws iam attach-role-policy --policy-arn arn:aws:iam::$ACCID:policy/${CLUSTER_NAME}_EKS_EBS_Policy --role-name ${CLUSTER_NAME}_EKS_EBS_role
helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
kubectl create ns ebs-csi
helm upgrade --install aws-ebs-csi-driver -n ebs-csi aws-ebs-csi-driver/aws-ebs-csi-driver
sleep 10
kubectl annotate serviceaccount ebs-csi-controller-sa -n ebs-csi eks.amazonaws.com/role-arn=arn:aws:iam::$ACCID:role/${CLUSTER_NAME}_EKS_EBS_role
until kubectl get pods -n ebs-csi -l=app=ebs-csi-controller|grep -i running >/dev/null; do  sleep 30; done
kubectl delete pods -n ebs-csi -l=app=ebs-csi-controller
rm ebs-iam-policy.json trust-policy.json -f
