
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$envFile = Join-Path $root '.env'
$exampleFile = Join-Path $root '.env.example'

function New-Secret([int]$byteCount = 32) {
    $bytes = New-Object byte[] $byteCount
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()

    try {
        $rng.GetBytes($bytes)
    }
    finally {
        $rng.Dispose()
    }

    return [Convert]::ToBase64String($bytes)
}


function New-SqlPassword {
    $bytes = New-Object byte[] 24
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()

    try {
        $rng.GetBytes($bytes)
    }
    finally {
        $rng.Dispose()
    }

    $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
    $password = 'Aa1!'

    foreach ($byte in $bytes) {
        $password += $chars[[int]($byte % $chars.Length)]
    }

    return $password
}

if (-not (Test-Path $exampleFile)) {
    throw 'Arquivo .env.example nao encontrado.'
}

if (-not (Test-Path $envFile)) {
    Copy-Item $exampleFile $envFile
    Write-Host 'Arquivo .env criado.'
}
else {
    Write-Host 'Arquivo .env existente preservado.'
}

$content = Get-Content $envFile -Raw

$values = @{
    'RABBITMQ_PASSWORD'    = New-Secret 24
    'SQLSERVER_SA_PASSWORD' = New-SqlPassword
    'JWT_SECRET_KEY'       = New-Secret 48
}

foreach ($key in $values.Keys) {
    $pattern = '(?m)^' + [regex]::Escape($key) + '=([^\r\n]*)'
    $match = [regex]::Match($content, $pattern)

    if ($match.Success) {
        $current = $match.Groups[1].Value.Trim().Trim('"').Trim("'")

        if (
            [string]::IsNullOrWhiteSpace($current) -or
            $current -eq 'DEFINIR_LOCALMENTE' -or
            ($key -eq 'JWT_SECRET_KEY' -and $current.Length -lt 32)
        ) {
            $replacement = $key + '=' + $values[$key]
            $content = [regex]::Replace(
                $content,
                $pattern,
                [System.Text.RegularExpressions.MatchEvaluator]{
                    param($m)
                    return $replacement
                }
            )
            Write-Host "$key configurada."
        }
    }
    else {
        $content = $content.TrimEnd() +
            [Environment]::NewLine +
            $key + '=' + $values[$key] +
            [Environment]::NewLine

        Write-Host "$key adicionada."
    }
}

[System.IO.File]::WriteAllText(
    $envFile,
    $content,
    (New-Object System.Text.UTF8Encoding($false))
)

Write-Host ''
Write-Host 'Configuracao inicial concluida.'
Write-Host 'O arquivo .env esta pronto para Docker Compose e Kubernetes.'
