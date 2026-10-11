#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Aviso: os secrets no projeto são exemplos para estudo; troque-os antes do deploy.
kubectl apply -f k8s/rabbitmq/rabbitmq.yaml
for repo in UsersAPI CatalogAPI PaymentsAPI NotificationsAPI; do
  if [[ -d "../$repo/k8s" ]]; then
    echo "Aplicando manifests de $repo"
    kubectl apply -f "../$repo/k8s"
  else
    echo "Ainda não há manifests em ../$repo/k8s; ignorando."
  fi
done
