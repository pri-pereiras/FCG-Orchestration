param([Parameter(Mandatory=$true)][string]$DockerHubUser, [string]$Tag='2.1')
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../../FCG_PaymentsAPI')).Path
$image = "$DockerHubUser/fcg-payments-api:$Tag"
docker build -t $image $repo
if ($LASTEXITCODE -ne 0) { throw 'Falha no docker build' }
docker push $image
if ($LASTEXITCODE -ne 0) { throw 'Falha no docker push. Execute docker login antes.' }
Write-Host "Publicado: $image"
