
$ErrorActionPreference = 'Stop'

# Diretório raiz do FCG-Orchestration
Set-Location (Join-Path $PSScriptRoot '..')

# Configurações
if (-not $env:RABBITMQ_USER) {
    $env:RABBITMQ_USER = 'fcg'
}

if (-not $env:RABBITMQ_PASSWORD) {
    throw 'Defina a variável RABBITMQ_PASSWORD antes do deploy.'
}

if (-not $env:PAYMENTS_IMAGE) {
    $env:PAYMENTS_IMAGE = 'pripereiras/fcg-payments-api:2.0'
}

function Apply-Manifest([string]$manifest) {
    $manifest | kubectl apply -f -

    if ($LASTEXITCODE -ne 0) {
        throw 'Falha ao aplicar manifesto Kubernetes.'
    }
}

Write-Host 'Criando Secrets do RabbitMQ...'

$secret = kubectl create secret generic rabbitmq-secret `
    --from-literal="RABBITMQ_DEFAULT_PASS=$env:RABBITMQ_PASSWORD" `
    --dry-run=client -o yaml

Apply-Manifest ($secret -join "`n")

Write-Host 'Criando Secrets do PaymentsAPI...'

$secret = kubectl create secret generic payments-api-secret `
    --from-literal="RabbitMq__Username=$env:RABBITMQ_USER" `
    --from-literal="RabbitMq__Password=$env:RABBITMQ_PASSWORD" `
    --from-literal='ConnectionStrings__PaymentsDb=Data Source=/app/data/payments-v2.db' `
    --dry-run=client -o yaml

Apply-Manifest ($secret -join "`n")

Write-Host 'Aplicando RabbitMQ...'
kubectl apply -f k8s/rabbitmq/rabbitmq.yaml

if ($LASTEXITCODE -ne 0) {
    throw 'Falha ao aplicar RabbitMQ.'
}

Write-Host 'Aplicando configurações do PaymentsAPI...'

kubectl apply `
    -f k8s/payments/pvc.yaml `
    -f k8s/payments/configmap.yaml `
    -f k8s/payments/service.yaml

if ($LASTEXITCODE -ne 0) {
    throw 'Falha ao aplicar configurações do PaymentsAPI.'
}

Write-Host "Configurando imagem: $env:PAYMENTS_IMAGE"

# Substitui a imagem definida no manifesto pela imagem configurada
$deployment = Get-Content k8s/payments/deployment.yaml -Raw

$deployment = $deployment -replace `
    '(?m)^(\s*image:\s*)\S*fcg-payments-api:\S+', `
    "`${1}$env:PAYMENTS_IMAGE"

Apply-Manifest $deployment

Write-Host 'Aguardando inicialização dos serviços...'

kubectl rollout status deployment/rabbitmq --timeout=180s

if ($LASTEXITCODE -ne 0) {
    throw 'RabbitMQ não iniciou corretamente.'
}

kubectl rollout status deployment/payments-api --timeout=180s

if ($LASTEXITCODE -ne 0) {
    throw 'PaymentsAPI não iniciou corretamente.'
}

Write-Host 'Verificando recursos Kubernetes...'

kubectl get deployments,pods,services,pvc

Write-Host 'Deploy concluído.'
