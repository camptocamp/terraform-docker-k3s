#!/bin/sh

set -e

eval "$(jq -r '@sh "CONTAINER_NAME=\(.container_name) CONTAINER_IP_ADDRESS=\(.container_ip_address)"')"

kubeconfig=$(docker exec "$CONTAINER_NAME" sed -e "s/127.0.0.1/$CONTAINER_IP_ADDRESS/" /etc/rancher/k3s/k3s.yaml)

jq -n --arg kubeconfig "$kubeconfig" '{"kubeconfig":$kubeconfig}'
