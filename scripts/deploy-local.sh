#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# 1. Carregar o .env automaticamente
if [[ ! -f .env ]]; then
  echo "ERRO: .env nao encontrado."
  echo "Crie o .env a partir do .env.example."
  exit 1
fi

while IFS='=' read -r key value || [[ -n "$key" ]]; do
  key="${key%$'\r'}"
  value="${value%$'\r'}"

  [[ -z "$key" || "$key" == \#* ]] && continue
  [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue

  # Remover aspas simples ou duplas externas
  if [[ "$value" == \"*\" && "$value" == *\" ]]; then
    value="${value:1:${#value}-2}"
  elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
    value="${value:1:${#value}-2}"
  fi

  export "$key=$value"
done < .env

echo "Configuracoes carregadas."

# 2. Validar configuracoes
: "${RABBITMQ_PASSWORD:?Informe RABBITMQ_PASSWORD}"
: "${SQLSERVER_SA_PASSWORD:?Informe SQLSERVER_SA_PASSWORD}"

if [[ "$RABBITMQ_PASSWORD" == "DEFINIR_LOCALMENTE" ||
      "$SQLSERVER_SA_PASSWORD" == "DEFINIR_LOCALMENTE" ]]; then
  echo "ERRO: configure as senhas no .env."
  exit 1
fi

RABBITMQ_USER="${RABBITMQ_USER:-fcg}"

USERS_IMAGE="${USERS_IMAGE:-pripereiras/fcg-users-api:1.0.0}"
CATALOG_IMAGE="${CATALOG_IMAGE:-pripereiras/fcg-catalog-api:1.0.2}"
PAYMENTS_IMAGE="${PAYMENTS_IMAGE:-pripereiras/fcg-payments-api:2.1}"
NOTIFICATIONS_IMAGE="${NOTIFICATIONS_IMAGE:-pripereiras/fcg-notifications-api:1.0.3}"

kubectl config current-context
kubectl cluster-info >/dev/null

# 3. Criar ou atualizar Secrets
echo "Configurando Secrets..."

apply_secret() {
  kubectl create secret generic "$1" "${@:2}" \
    --dry-run=client -o yaml | kubectl apply -f -
}

apply_secret rabbitmq-secret \
  --from-literal="RABBITMQ_DEFAULT_PASS=$RABBITMQ_PASSWORD"

apply_secret rabbitmq-client-secret \
  --from-literal="RabbitMq__Username=$RABBITMQ_USER" \
  --from-literal="RabbitMq__Password=$RABBITMQ_PASSWORD"

apply_secret payments-api-secret \
  --from-literal="RabbitMq__Username=$RABBITMQ_USER" \
  --from-literal="RabbitMq__Password=$RABBITMQ_PASSWORD" \
  --from-literal="ConnectionStrings__PaymentsDb=Data Source=/app/data/payments-v2.db"

apply_secret catalog-sqlserver-secret \
  --from-literal="MSSQL_SA_PASSWORD=$SQLSERVER_SA_PASSWORD"

apply_secret catalog-api-secret \
  --from-literal="RabbitMq__Username=$RABBITMQ_USER" \
  --from-literal="RabbitMq__Password=$RABBITMQ_PASSWORD"

# 4. Configurar JWT da UsersAPI
if [[ -z "${JWT_SECRET_KEY:-}" ||
      "$JWT_SECRET_KEY" == "DEFINIR_LOCALMENTE" ||
      ${#JWT_SECRET_KEY} -lt 32 ]]; then

  JWT_SECRET_KEY="$(
    kubectl get secret users-api-secret \
      -o jsonpath='{.data.Jwt__SecretKey}' \
      --ignore-not-found | base64 --decode
  )"

  if [[ -z "$JWT_SECRET_KEY" ]]; then
    JWT_SECRET_KEY="$(head -c 48 /dev/urandom | base64 | tr -d '\r\n')"
    echo "Nova chave JWT gerada."
  else
    echo "Chave JWT existente reutilizada."
  fi
fi

if [[ ${#JWT_SECRET_KEY} -lt 32 ]]; then
  echo "ERRO: chave JWT invalida."
  exit 1
fi

apply_secret users-api-secret \
  --from-literal="Jwt__SecretKey=$JWT_SECRET_KEY"

# 5. Infraestrutura compartilhada
echo "Aplicando infraestrutura..."

kubectl apply -f k8s/rabbitmq/rabbitmq.yaml

kubectl apply \
  -f k8s/catalog/sqlserver-pvc.yaml \
  -f k8s/catalog/sqlserver.yaml

# 6. ConfigMaps, Services e volumes
kubectl apply \
  -f k8s/payments/pvc.yaml \
  -f k8s/payments/configmap.yaml \
  -f k8s/payments/service.yaml

for service in catalog users notifications; do
  kubectl apply \
    -f "k8s/${service}/configmap.yaml" \
    -f "k8s/${service}/service.yaml"
done

# 7. Deployments com as imagens configuradas
apply_image() {
  local file="$1"
  local image="$2"
  local image_name="$3"

  sed -E \
    "s|(^[[:space:]]*image: ).*${image_name}:.*|\1${image}|" \
    "$file" | kubectl apply -f -
}

echo "Aplicando microsservicos..."

apply_image k8s/payments/deployment.yaml \
  "$PAYMENTS_IMAGE" "fcg-payments-api"

apply_image k8s/catalog/deployment.yaml \
  "$CATALOG_IMAGE" "fcg-catalog-api"

apply_image k8s/users/deployment.yaml \
  "$USERS_IMAGE" "fcg-users-api"

apply_image k8s/notifications/deployment.yaml \
  "$NOTIFICATIONS_IMAGE" "fcg-notifications-api"

# 8. Conferir disponibilidade
for deployment in \
  rabbitmq sqlserver payments-api catalog-api users-api notifications-api
do
  echo "Verificando $deployment..."
  kubectl rollout status "deployment/$deployment" --timeout=240s
done

echo "Estado final:"
kubectl get deployments,pods,services,pvc

echo "Deploy concluido."
