$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
if (-not $env:DOCKERHUB_USERNAME -or $env:DOCKERHUB_USERNAME -eq 'SEU_USUARIO_DOCKERHUB') { throw 'Defina $env:DOCKERHUB_USERNAME' }
if (-not $env:RABBITMQ_PASSWORD) { throw 'Defina $env:RABBITMQ_PASSWORD' }
if (-not $env:RABBITMQ_USER) { $env:RABBITMQ_USER = 'fcg' }
if (-not $env:PAYMENTS_TAG) { $env:PAYMENTS_TAG = '2.1' }
function Apply-Manifest([string]$manifest) {
  $manifest | kubectl apply -f -
  if ($LASTEXITCODE -ne 0) { throw 'Falha ao aplicar manifesto' }
}
$secret = kubectl create secret generic rabbitmq-secret --from-literal="RABBITMQ_DEFAULT_PASS=$env:RABBITMQ_PASSWORD" --dry-run=client -o yaml
Apply-Manifest ($secret -join "`n")
$secret = kubectl create secret generic payments-api-secret --from-literal="RabbitMq__Username=$env:RABBITMQ_USER" --from-literal="RabbitMq__Password=$env:RABBITMQ_PASSWORD" --from-literal='ConnectionStrings__PaymentsDb=Data Source=/app/data/payments-v2.db' --dry-run=client -o yaml
Apply-Manifest ($secret -join "`n")
kubectl apply -f k8s/rabbitmq/rabbitmq.yaml
kubectl apply -f k8s/payments/pvc.yaml -f k8s/payments/configmap.yaml -f k8s/payments/service.yaml
$deployment = (Get-Content k8s/payments/deployment.yaml -Raw).Replace('SEU_USUARIO_DOCKERHUB/fcg-payments-api:2.1', "$env:DOCKERHUB_USERNAME/fcg-payments-api:$env:PAYMENTS_TAG")
Apply-Manifest $deployment
kubectl rollout status deployment/rabbitmq --timeout=180s
kubectl rollout status deployment/payments-api --timeout=180s
kubectl get deployments,pods,services,pvc
