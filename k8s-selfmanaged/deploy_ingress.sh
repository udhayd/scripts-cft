#! /bin/bash
### Script to deploy ingress controller
kubectl create ns ingress
curl -s https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3|bash
git clone https://github.com/udhayd/traefik
cd traefik/chart/
helm dep update
helm install ingress . -n ingress

#lbip=$(aws ec2 describe-instances --query 'Reservations[*].Instances[*].[PublicIpAddress,Tags[?Key==\`Name\`].Value|[0],LaunchTime,State.Name]' --output text|column -t|grep -i running|grep nginx|awk '{print $1}')
lbip=$(grep loadbalancer /etc/hosts|awk '{print $1}')
echo "
spec:
  externalIPs:
    - $lbip" >/tmp/spec.yaml
kubectl patch svc ingress-traefik --type merge --patch  "$(cat /tmp/spec.yaml)" -n ingress

#### Update DNS Record
lbip=$(grep loadbalancer /etc/hosts|awk '{print $1}')
KEY="LSA2GRkEwF7voysIuaisgwQ11Zc7uXzCaaJDrUXp";
ZONE_ID="d8c45322d88ecc995996bda2ab7c1553";
NAME="*.groofy.help";
SDNS_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$NAME" \
-H "Authorization: Bearer $KEY" \
-H "Content-Type: application/json" \
| python -m json.tool|grep -w "id"|awk -F':' '{print $2}'|sed -e 's/"//g' -e 's/,//g' -e 's/ //g')

DNS_ID="$SDNS_ID";
TYPE="A";
NAME="*.groofy.help";
CONTENT="$lbip";
PROXIED="false";
TTL="1";
curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$DNS_ID" \
-H "Authorization: Bearer $KEY" \
-H "Content-Type: application/json" \
--data '{"type":"'"$TYPE"'","name":"'"$NAME"'","content":"'"$CONTENT"'","proxied":'"$PROXIED"',"ttl":'"$TTL"'}' | python -m json.tool;