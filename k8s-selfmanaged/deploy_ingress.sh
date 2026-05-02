#! /bin/bash
### Script to deploy ingress controller
shopt -s expand_aliases

## Variables
export DOMAIN="groofy.xyz"
TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`
export AWS_DEFAULT_REGION=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/\(.*\)[a-z]/\1/')
alias python=/usr/bin/python3

## Deploy Ingress controller
curl -s https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3|bash
kubectl create ns ingress
git clone https://github.com/udhayd/traefik
cd traefik/chart/
helm dep update
helm install ingress . -n ingress

## Update Ingress service
lbip=$(aws ec2 describe-instances --query 'Reservations[*].Instances[*].[PublicIpAddress,Tags[?Key==`Name`].Value|[0],LaunchTime,State.Name]'  --filters Name=instance-state-name,Values=running  --output text|column -t|grep nginx|awk '{print $1}')
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
kubectl create ing ing --rule="app.$DOMAIN/*=ui:80"
