$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../../FCG_PaymentsAPI')).Path
dotnet test (Join-Path $repo 'Payments.sln') --configuration Release
if ($LASTEXITCODE -ne 0) { throw 'Falha nos testes automatizados' }
$base = 'http://localhost:8082'
foreach ($path in @('/health','/ready')) {
  $response = Invoke-WebRequest -Uri "$base$path" -UseBasicParsing
  if ($response.StatusCode -ne 200) { throw "$path retornou $($response.StatusCode)" }
  Write-Host "$path OK"
}
Write-Host 'Atenção: para fluxo E2E falta publicar OrderPlacedEvent real, verificar banco e consumidores.'
