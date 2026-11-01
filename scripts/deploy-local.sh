
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Configuracoes
: "${RABBITMQ_PASSWORD:?Defina RABBITMQ_PASSWORD}"

RABBITMQ_USER="${RABBITMQ_USER:-fcg}"
PAYMENTS_IMAGE="${PAYMENTS_IMAGE:-pripereiras/fcg-payments-api:2.0}"

# Validar ambiente Kubernetes
kubectl cluster-info >/dev/null

echo "Criando Secrets..."

kubectl create secret generic rabbitmq-secret \
  --from-literal="RABBITMQ_DEFAULT_PASS=${RABBITMQ_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic payments-api-secret \
  --from-literal="RabbitMq__Username=${RABBITMQ_USER}" \
  --from-literal="RabbitMq__Password=${RABBITMQ_PASSWORD}" \
  --from-literal="ConnectionStrings__PaymentsDb=Data Source=/app/data/payments-v2.db" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Aplicando RabbitMQ..."
kubectl apply -f k8s/rabbitmq/rabbitmq.yaml

echo "Aplicando PaymentsAPI..."
kubectl apply \
  -f k8s/payments/pvc.yaml \
  -f k8s/payments/configmap.yaml \
  -f k8s/payments/service.yaml

# Aplicar o Deployment com a imagem configurada
sed -E \
  "s|(^[[:space:]]*image: ).*fcg-payments-api:.*|\1${PAYMENTS_IMAGE}|" \
  k8s/payments/deployment.yaml | kubectl apply -f -

echo "Aguardando Deployments..."

kubectl rollout status deployment/rabbitmq --timeout=180s
kubectl rollout status deployment/payments-api --timeout=180s

echo "Estado atual do cluster:"
kubectl get deployments,pods,services,pvc

echo "Deploy concluido."
