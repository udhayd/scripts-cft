#! /bin/bash
### Script to deploy ingress controller
kubelctl create ns ingress
curl -s https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3|bash
git clone https://github.com/udhayd/traefik
cd traefik/chart/
helm dep update
helm install ingress . -n ingress

lbip=$(aws ec2 describe-instances --query 'Reservations[*].Instances[*].[PublicIpAddress,Tags[?Key==\`Name\`].Value|[0],LaunchTime,State.Name]' --output text|column -t|grep nginx|awk '{print $1}')
echo "
spec:
  externalIPs:
    - $lbip" >/tmp/spec.yaml
kubectl patch svc ingress-traefik --type merge --patch  "$(cat /tmp/spec.yaml)" -n ingress
