$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')


# Carregar configuracoes do arquivo .env
$envFile = Join-Path (Get-Location) '.env'

if (-not (Test-Path $envFile)) {
    throw "Arquivo .env nao encontrado. Copie .env.example para .env e configure as credenciais."
}

Get-Content $envFile | ForEach-Object {
    $line = $_.Trim()

    if ($line -and -not $line.StartsWith('#')) {
        $parts = $line -split '=', 2

        if ($parts.Count -eq 2) {
            $key = $parts[0].Trim()
            $value = $parts[1].Trim().Trim('"').Trim("'")

            if ($key -match '^[A-Za-z_][A-Za-z0-9_]*$') {
                [Environment]::SetEnvironmentVariable(
                    $key,
                    $value,
                    'Process'
                )
            }
        }
    }
}

Write-Host "Configuracoes do .env carregadas."


function Assert-Ok([string]$step) {
    if ($LASTEXITCODE -ne 0) { throw "Falha: $step" }
}
function Apply-Yaml([string[]]$yaml) {
    $yaml | kubectl apply -f -
    Assert-Ok 'kubectl apply -f -'
}
function Apply-Image([string]$file, [string]$image, [string]$pattern) {
    $yaml = Get-Content $file -Raw
    $replacement = '${1}' + $image
    $yaml = [regex]::Replace($yaml, $pattern, $replacement)
    Apply-Yaml @($yaml)
}

if (-not $env:RABBITMQ_USER) { $env:RABBITMQ_USER = 'fcg' }
if (-not $env:RABBITMQ_PASSWORD -or $env:RABBITMQ_PASSWORD -eq 'DEFINIR_LOCALMENTE') { throw 'Defina RABBITMQ_PASSWORD no ambiente.' }
if (-not $env:SQLSERVER_SA_PASSWORD -or $env:SQLSERVER_SA_PASSWORD -eq 'DEFINIR_LOCALMENTE') { throw 'Defina SQLSERVER_SA_PASSWORD no ambiente.' }
if (-not $env:USERS_IMAGE) { $env:USERS_IMAGE = 'gustavotianosilva/fcg-users-api:1.0.0' }
if (-not $env:CATALOG_IMAGE) { $env:CATALOG_IMAGE = 'pripereiras/fcg-catalog-api:1.0.0' }
if (-not $env:PAYMENTS_IMAGE) { $env:PAYMENTS_IMAGE = 'pripereiras/fcg-payments-api:2.0' }
if (-not $env:NOTIFICATIONS_IMAGE) { $env:NOTIFICATIONS_IMAGE = 'pripereiras/fcg-notifications-api:1.0.1' }

kubectl config current-context
Assert-Ok 'contexto Kubernetes'
Write-Host 'AVISO: secrets do Kubernetes serao atualizados. A senha do usuario fcg em broker persistido NAO muda automaticamente.'

Apply-Yaml @(kubectl create secret generic rabbitmq-secret --from-literal="RABBITMQ_DEFAULT_PASS=$env:RABBITMQ_PASSWORD" --dry-run=client -o yaml)
Assert-Ok 'rabbitmq-secret'
Apply-Yaml @(kubectl create secret generic rabbitmq-client-secret --from-literal="RabbitMq__Username=$env:RABBITMQ_USER" --from-literal="RabbitMq__Password=$env:RABBITMQ_PASSWORD" --dry-run=client -o yaml)
Assert-Ok 'rabbitmq-client-secret'
Apply-Yaml @(kubectl create secret generic payments-api-secret --from-literal="RabbitMq__Username=$env:RABBITMQ_USER" --from-literal="RabbitMq__Password=$env:RABBITMQ_PASSWORD" --from-literal='ConnectionStrings__PaymentsDb=Data Source=/app/data/payments-v2.db' --dry-run=client -o yaml)
Assert-Ok 'payments-api-secret'
Apply-Yaml @(kubectl create secret generic catalog-sqlserver-secret --from-literal="MSSQL_SA_PASSWORD=$env:SQLSERVER_SA_PASSWORD" --dry-run=client -o yaml)
Assert-Ok 'catalog-sqlserver-secret'
# Encadeamento do SQLSERVER_PASSWORD dentro do pod (Kubernetes expande $(VAR) na ordem de declaracao).
$catalogSecret = kubectl create secret generic catalog-api-secret --from-literal="RabbitMq__Username=$env:RABBITMQ_USER" --from-literal="RabbitMq__Password=$env:RABBITMQ_PASSWORD" --dry-run=client -o yaml
Apply-Yaml @($catalogSecret)
Assert-Ok 'catalog-api-secret'


# JWT da UsersAPI
$jwtKey = $env:JWT_SECRET_KEY

if (-not $jwtKey -or  $jwtKey -eq 'DEFINIR_LOCALMENTE' -or $jwtKey.Length -lt 32 ) {
    $existing = kubectl get secret users-api-secret `
        -o jsonpath='{.data.Jwt__SecretKey}' `
        --ignore-not-found

    if ($LASTEXITCODE -ne 0) {
        throw 'Falha ao consultar o Secret da UsersAPI.'
    }

    if ($existing) {
        $jwtKey = [System.Text.Encoding]::UTF8.GetString(
            [Convert]::FromBase64String($existing)
        )
        Write-Host 'Reutilizando chave JWT existente.'
    }
    else {
        $bytes = New-Object byte[] 48
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        try {
            $rng.GetBytes($bytes)
        }
        finally {
            $rng.Dispose()
        }

        $jwtKey = [Convert]::ToBase64String($bytes)
        Write-Host 'Nova chave JWT gerada.'
    }
}

if ($jwtKey.Length -lt 32) {
    throw 'JWT_SECRET_KEY deve ter pelo menos 32 caracteres.'
}

$usersSecret = kubectl create secret generic users-api-secret `
    --from-literal="Jwt__SecretKey=$jwtKey" `
    --dry-run=client -o yaml

if ($LASTEXITCODE -ne 0) {
    throw 'Falha ao criar o Secret JWT.'
}

Apply-Yaml @($usersSecret)

Write-Host 'Secret JWT da UsersAPI configurado.'

kubectl apply -f k8s/rabbitmq/rabbitmq.yaml
Assert-Ok 'rabbitmq'
kubectl apply -f k8s/catalog/sqlserver-pvc.yaml -f k8s/catalog/sqlserver.yaml
Assert-Ok 'sqlserver'
kubectl apply -f k8s/payments/pvc.yaml -f k8s/payments/configmap.yaml -f k8s/payments/service.yaml
Assert-Ok 'payments base'
kubectl apply -f k8s/catalog/configmap.yaml -f k8s/catalog/service.yaml
Assert-Ok 'catalog base'
kubectl apply -f k8s/users/configmap.yaml -f k8s/users/service.yaml
Assert-Ok 'users base'
kubectl apply -f k8s/notifications/configmap.yaml -f k8s/notifications/service.yaml
Assert-Ok 'notifications base'

# O deployment catalog usa senha SQLServer em env referenciada via Secret e variavel expandida no proprio pod.
Apply-Image 'k8s/payments/deployment.yaml' $env:PAYMENTS_IMAGE '(?m)^(\s*image:\s*)\S*fcg-payments-api:\S+'
Apply-Image 'k8s/catalog/deployment.yaml' $env:CATALOG_IMAGE '(?m)^(\s*image:\s*)\S*fcg-catalog-api:\S+'
Apply-Image 'k8s/users/deployment.yaml' $env:USERS_IMAGE '(?m)^(\s*image:\s*)\S*fcg-users-api:\S+'
Apply-Image 'k8s/notifications/deployment.yaml' $env:NOTIFICATIONS_IMAGE '(?m)^(\s*image:\s*)\S*fcg-notifications-api:\S+'

foreach ($name in @('rabbitmq','sqlserver','payments-api','catalog-api','users-api','notifications-api')) {
    Write-Host "Aguardando $name..."
    kubectl rollout status "deployment/$name" --timeout=240s
    if ($LASTEXITCODE -ne 0) { Write-Warning "Rollout pendente: $name. Inspecione kubectl describe/logs." }
}
kubectl get deployments,pods,services,pvc
Write-Host 'Deploy aplicado. Verifique os logs e os contratos RabbitMQ antes de considerar integracao concluida.'
