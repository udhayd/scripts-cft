#! /bin/bash
### Script to deploy ingress controller
kubelctl create ns ingress
curl -s https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3|bash
git clone https://github.com/udhayd/traefik
cd traefik/chart/
helm dep update
helm install ingress . -n ingress
