#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DOCKERHUB_USERNAME:?Informe DOCKERHUB_USERNAME}" 
: "${RABBITMQ_PASSWORD:?Informe RABBITMQ_PASSWORD}" 
PAYMENTS_TAG="${PAYMENTS_TAG:-2.1}"
RABBITMQ_USER="${RABBITMQ_USER:-fcg}"
if [[ "$DOCKERHUB_USERNAME" == 'SEU_USUARIO_DOCKERHUB' ]]; then echo 'Troque o usuario Docker Hub'; exit 1; fi
kubectl create secret generic rabbitmq-secret --from-literal=RABBITMQ_DEFAULT_PASS="$RABBITMQ_PASSWORD" --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic payments-api-secret   --from-literal=RabbitMq__Username="$RABBITMQ_USER"   --from-literal=RabbitMq__Password="$RABBITMQ_PASSWORD"   --from-literal='ConnectionStrings__PaymentsDb=Data Source=/app/data/payments-v2.db'   --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f k8s/rabbitmq/rabbitmq.yaml
kubectl apply -f k8s/payments/pvc.yaml -f k8s/payments/configmap.yaml -f k8s/payments/service.yaml
sed "s|SEU_USUARIO_DOCKERHUB/fcg-payments-api:2.1|${DOCKERHUB_USERNAME}/fcg-payments-api:${PAYMENTS_TAG}|" k8s/payments/deployment.yaml | kubectl apply -f -
kubectl rollout status deployment/rabbitmq --timeout=180s
kubectl rollout status deployment/payments-api --timeout=180s
kubectl get deployments,pods,services,pvc
