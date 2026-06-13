#! /bin/bash
### Script to deploy ingress controller
shopt -s expand_aliases

## Variables
export DOMAIN="groofy.xyz"
TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`
export AWS_DEFAULT_REGION=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/\(.*\)[a-z]/\1/')
alias python=/usr/bin/python3

## Install helm
curl -s https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3|bash

## Deploy kubernetes metrics server
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm install metrics-server metrics-server/metrics-server --set args[0]="--kubelet-insecure-tls" -n kube-system

## Deploy Istio service mesh
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update
helm install istio-base istio/base -n istio-system --set defaultRevision=default --create-namespace
helm install istiod istio/istiod -n istio-system
helm install istio-gateway istio/gateway -n istio-gateways --create-namespace

## Deploy Ingress controller
git clone https://github.com/udhayd/traefik
cd traefik/chart/;helm dep update
helm install ingress . -n ingress --create-namespace

## Update Ingress service
lbip=$(aws ec2 describe-instances --query 'Reservations[*].Instances[*].[PublicIpAddress,Tags[?Key==`Name`].Value|[0],LaunchTime,State.Name]'  --filters Name=instance-state-name,Values=running  --output text|column -t|grep nginx-traefik|awk '{print $1}')
echo "
spec:
  externalIPs:
    - $lbip" >/tmp/spec.yaml
kubectl patch svc ingress-traefik --type merge --patch  "$(cat /tmp/spec.yaml)" -n ingress

## Update DNS Record
KEY="cfut_pv6Iw5cTfq7IHuOww2pJUvu0c2fHOnJBP84PHqy019baa0fc"
ZONE_ID="55b113f292238697b00874ce460f220b"
NAME="*.$DOMAIN"
SDNS_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$NAME" \
-H "Authorization: Bearer $KEY" \
-H "Content-Type: application/json" \
| python -m json.tool|grep -w "id"|awk -F':' '{print $2}'|sed -e 's/"//g' -e 's/,//g' -e 's/ //g')

DNS_ID="$SDNS_ID";
TYPE="A";
NAME="*.$DOMAIN";
CONTENT="$lbip";
PROXIED="false";
TTL="1";
curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$DNS_ID" \
-H "Authorization: Bearer $KEY" \
-H "Content-Type: application/json" \
--data '{"type":"'"$TYPE"'","name":"'"$NAME"'","content":"'"$CONTENT"'","proxied":'"$PROXIED"',"ttl":'"$TTL"'}' | python -m json.tool;


## Deploy Sample application
kubectl apply -f https://github.com/aws-containers/retail-store-sample-app/releases/latest/download/kubernetes.yaml
kubectl wait --for=condition=available deployments --all

## Configure ingress rule
kubectl create ing ing --rule="app.$DOMAIN/*=ui:80"

## Configure Virtualservice/Gateway
kubectl get secret default-cert -n ingress -o yaml >/tmp/a.yaml
sed -i 's/namespace: ingress/namespace: istio-gateways/g' /tmp/a.yaml
sed -i 's/name: default-cert/name: istio-gateway-certs/g' /tmp/a.yaml
sed -i 's/type: Opaque/type: kubernetes.io\/tls/g' /tmp/a.yaml
cat >/tmp/vs.yaml <<EOF
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: app-gateway
  namespace: istio-gateways
spec:
  # The selector matches the ingress gateway pod labels.
  # If you installed Istio using Helm following the standard documentation, this would be "istio=ingress"
  selector:
    istio: gateway # use istio default controller
  servers:
  - port:
      number: 443
      name: https
      protocol: HTTPS
    tls:
      mode: SIMPLE
      credentialName: istio-gateway-certs
    hosts:
    - "app.istio.groofy.xyz"
---
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: app
spec:
  hosts:
  - "app.istio.groofy.xyz"
  gateways:
  - istio-gateways/app-gateway
  http:
  - match:
    - uri:
        prefix: /
    route:
    - destination:
        host: ui
        port:
          number: 80
EOF
kubectl apply -f /tmp/vs.yaml
