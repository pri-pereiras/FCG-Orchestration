# FCG-Orchestration — Fase 2 FIAP

Repositório central de **manifests Kubernetes, Docker Compose e scripts de implantação**. Os quatro códigos-fonte e respectivos Dockerfiles continuam em repositórios Git independentes. **O Git guarda os nomes das imagens e configurações, não os arquivos binários das imagens Docker**. O Docker Hub armazena as imagens e o Kubernetes faz pull.

## Status real

- `PaymentsAPI`: manifestos reais centralizados em `k8s/payments`, Compose via imagem do Docker Hub, testes automatizados existentes.
- `RabbitMQ`: manifestos em `k8s/rabbitmq`.
- `UsersAPI`, `CatalogAPI`, `NotificationsAPI`: pastas reservadas, aguardando código e configurações dos repositórios; ainda **não** executáveis a partir daqui.
- **Decisão validada com o professor:** todos os manifestos Kubernetes ficam exclusivamente neste repositório (`FCG-Orchestration/k8s`). Os repositórios de microsserviços devem manter código-fonte, Dockerfile e testes, sem pastas `/k8s` duplicadas.

## 1. Publicar PaymentsAPI no Docker Hub (PowerShell)

Coloque os repositórios `FCG_PaymentsAPI` e `FCG-Orchestration` lado a lado. No terminal:

```powershell
docker login
cd FCG-Orchestration
.\scripts\publish-payments.ps1 -DockerHubUser SEU_USUARIO -Tag 2.1
```

A imagem publicada será `SEU_USUARIO/fcg-payments-api:2.1`. Não há necessidade de copiar o código da API para este repositório. Repetir a publicação para novas versões com **tags específicas**, evitando depender de `latest`.

## 2. Docker Compose: executar imagens publicadas

```powershell
Copy-Item .env.example .env
# Edite .env com DOCKERHUB_USERNAME e RABBITMQ_PASSWORD real
# docker compose lê .env automaticamente
docker compose pull
docker compose up -d
docker compose ps
docker compose logs -f payments-api
```

Endpoints: `http://localhost:8082/health`, `/ready`, `/swagger` e `/dashboard` (modo Development); RabbitMQ Management em `http://localhost:15672`. No Compose, após o primeiro pull, o código-fonte não precisa estar presente.

## 3. Kubernetes local (Docker Desktop)

Kubernetes habilitado e `kubectl config current-context` apontando para o cluster desejado. **Não execute o script contra um cluster de produção.** Configure as variáveis na sessão PowerShell:

```powershell
$env:DOCKERHUB_USERNAME = 'SEU_USUARIO'
$env:PAYMENTS_TAG = '2.1'
$env:RABBITMQ_USER = 'fcg'
$env:RABBITMQ_PASSWORD = 'SENHA_FORTE_QUE_VOCE_ESCOLHEU'
.\scripts\deploy-local.ps1
kubectl get deployments,pods,services,pvc
kubectl port-forward svc/payments-api 8082:80
```

Para Bash/Linux/macOS: `export DOCKERHUB_USERNAME=... RABBITMQ_PASSWORD=...; bash scripts/deploy-local.sh`. Os scripts criam os Secrets pelo cliente do kubectl, sem salvar a senha em arquivos versionados. Ainda assim, **comandos de terminal podem aparecer no histórico**: use um gerenciador de segredos em ambientes reais.

Se o repositório Docker Hub for privado, crie um `imagePullSecret` (`docker-registry`) e referencie-o no Deployment (não versione credenciais). Imagens públicas dispensam isso.

**Obs.:** a API usa SQLite em PVC ReadWriteOnce, uma única réplica e estratégia Recreate. Não escalar horizontalmente neste estágio. RabbitMQ neste exemplo tem armazenamento efêmero.

## 4. Testes PaymentsAPI

```powershell
.\scripts\test-payments.ps1
kubectl logs deploy/payments-api --tail=100
kubectl logs deploy/rabbitmq --tail=100
```

O script roda `dotnet test` e valida `/health` e `/ready` do **Compose** em localhost:8082 (não teste o localhost se só fez deploy K8s sem port-forward). Para teste de evento ponta a ponta, publicar `Fcg.Contracts:OrderPlacedEvent` via MassTransit, consultar `GET /api/payments/{orderId}` e verificar o `PaymentProcessedEvent` e o consumidor real do Catalog/Notifications. Não basta o health check para certificar esses fluxos.

## 5. Integração dos outros serviços

Para cada serviço, receber Dockerfile, tag publicada no Docker Hub, porta, nomes de Service, configurações não sensíveis, segredos necessários e endpoints de health. Criar e manter os manifestos somente aqui. Adicionar `k8s/<servico>/` neste repositório e uma entrada `image: <usuario>/<imagem>:<tag>` no Deployment. Aplicar em ordem de dependência; acrescentar os serviços no Compose para cumprir o `docker compose up` da aplicação completa.

**Organização confirmada com o professor:** quatro repositórios independentes para código/Dockerfile, mais o `FCG-Orchestration` com os manifestos Deployment, Service, ConfigMap e Secret (segredos criados na implantação, sem credenciais em texto aberto). Dockerfiles multi-stage, fluxos end-to-end, Compose completo e deploy Kubernetes continuam como critérios técnicos. Esta entrega ainda não demonstra os quatro serviços.

## 6. Migração dos manifestos para um único repositório

Em cada repositório de microsserviço onde exista uma pasta `k8s`, remova-a **do Git** depois de confirmar que os manifests necessários foram incorporados ao `FCG-Orchestration/k8s/<servico>`:

```powershell
git rm -r k8s
git commit -m "chore: centraliza manifestos k8s no FCG-Orchestration"
git push
```

Não apague Dockerfile, código, testes ou contratos dos microsserviços. Publique a imagem no Docker Hub; o `FCG-Orchestration` referencia sua tag no `Deployment` e no `docker-compose.yml`.
