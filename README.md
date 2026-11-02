# FCG-Orchestration — FIAP | Tech Challenge Fase 2

Repositório central de **orquestração**, sem código-fonte ou Dockerfiles dos microsserviços. Reúne **Docker Compose, manifestos Kubernetes, scripts e documentação**. Cada API possui repositório próprio e publica sua imagem no Docker Hub.

## 1. Arquitetura e imagens

| Componente | Imagem | Porta local (Compose) | Endereço interno no Kubernetes |
|---|---|---|---|
| UsersAPI | `pripereiras/fcg-users-api:1.0.0` | `8080` | `users-api:80` → container `8080` |
| CatalogAPI | `pripereiras/fcg-catalog-api:1.0.2` | `8081` | `catalog-api:80` → container `8080` |
| PaymentsAPI | `pripereiras/fcg-payments-api:2.1` | `8082` | `payments-api:80` → container `8080` |
| NotificationsAPI | `pripereiras/fcg-notifications-api:1.0.3` | `8083` | `notifications-api:80` → container `8080` |
| RabbitMQ | `rabbitmq:3.13-management` | AMQP `5674`, painel `15674` | `rabbitmq:5672`, painel `rabbitmq:15672` |
| SQL Server | `mcr.microsoft.com/mssql/server:2022-latest` | Sem exposição externa | `sqlserver:1433` |

**Importante:** as portas do computador não são as portas usadas entre containers. As APIs acessam RabbitMQ em `rabbitmq:5672` e SQL Server em `sqlserver:1433`, tanto no Compose quanto no Kubernetes (usando os respectivos Services). `localhost` dentro de um container ou Pod não aponta para outro serviço.

### Persistência

- **UsersAPI:** SQL Server, banco lógico `FcgUsersDb`.
- **CatalogAPI:** mesmo servidor SQL Server, banco lógico `CatalogDb`.
- **PaymentsAPI:** SQLite com volume persistente.
- **RabbitMQ:** volume persistente no Compose; o manifesto Kubernetes atual não configura PVC para o broker.

## 2. Pré-requisitos

- Docker Desktop com Docker Compose; para Kubernetes, habilitar o cluster local do Docker Desktop.
- PowerShell no Windows; para scripts `.sh`, Bash com `kubectl` e `base64` disponíveis.
- Acesso às imagens públicas no Docker Hub.
- Memória suficiente para SQL Server e as quatro APIs.

## 3. Primeira configuração — Windows PowerShell

Na raiz deste repositório, execute:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup.ps1
```

O `setup.ps1` cria o `.env` a partir do `.env.example` quando necessário, gera senhas e uma chave JWT para valores ausentes ou placeholders e **preserva configurações existentes**. Execute-o antes de iniciar os serviços. As senhas e a chave JWT ficam apenas no `.env` local; o `.env.example` contém placeholders e pode ser versionado.

Confira que o arquivo está ignorado pelo Git:

```powershell
git check-ignore .env
```

**Não compartilhe ou versione o `.env`.** O setup não redefine automaticamente credenciais de um RabbitMQ ou SQL Server com dados persistidos: ao reutilizar volumes antigos, mantenha as credenciais originais.

Em Linux/macOS, crie o `.env` a partir de `.env.example` e preencha `RABBITMQ_PASSWORD`, `SQLSERVER_SA_PASSWORD` e `JWT_SECRET_KEY` (mínimo de 32 caracteres) com valores fortes. O script Bash de deploy lê o `.env`.

## 4. Executar com Docker Compose

```powershell
docker compose config --quiet
docker compose pull
docker compose up -d
docker compose ps
```

**Acessos locais:**

- UsersAPI: `http://localhost:8080/health` (HTTP 200 confirmado).
- CatalogAPI: `http://localhost:8081/swagger/index.html` (HTTP 200 confirmado). A imagem atual retorna 404 em `/health`.
- PaymentsAPI: `http://localhost:8082/health` (HTTP 200 confirmado).
- NotificationsAPI: `http://localhost:8083` (a rota HTTP exata deve ser consultada no projeto).
- Painel RabbitMQ: `http://localhost:15674` (credenciais definidas no `.env`).

Logs:

```powershell
docker compose logs --tail=100 users-api
docker compose logs --tail=100 catalog-api
docker compose logs --tail=100 payments-api
docker compose logs --tail=100 notifications-api
```

**Validação realizada:** os seis containers iniciaram em conjunto; RabbitMQ e SQL Server ficaram `healthy`; UsersAPI e PaymentsAPI retornaram HTTP 200 em `/health`; CatalogAPI respondeu no Swagger e executou suas migrações; NotificationsAPI iniciou e registrou `Bus started: rabbitmq://rabbitmq/`.

Para encerrar sem remover os volumes:

```powershell
docker compose down
```

**Não utilize `docker compose down -v` para corrigir erros de senha**: essa opção elimina volumes e dados persistidos.

## 5. Executar com Kubernetes (Docker Desktop)

Confirme o contexto antes de executar:

```powershell
kubectl config current-context
```

Para o ambiente local do projeto, o contexto esperado é `docker-desktop`. **O script utiliza o namespace e o contexto ativos e pode atualizar recursos existentes. Não o execute em produção.**

No Windows, após executar o `setup.ps1`:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-local.ps1
kubectl get deployments,pods,services,pvc
```

No Linux/macOS/Git Bash, após configurar o `.env`:

```bash
bash scripts/deploy-local.sh
kubectl get deployments,pods,services,pvc
```

Os scripts utilizam as imagens definidas no `.env`, criam/atualizam os Secrets necessários, aplicam os manifestos e verificam os rollouts. O Secret `users-api-secret` guarda a chave JWT; o script PowerShell reutiliza a chave existente quando o `.env` não define outra. Os demais Secrets incluem credenciais do RabbitMQ, SQL Server e configurações de cada API.

**Validação realizada:** os seis Deployments (`users-api`, `catalog-api`, `payments-api`, `notifications-api`, `rabbitmq` e `sqlserver`) ficaram `1/1` no Kubernetes. UsersAPI e CatalogAPI utilizaram SQL Server; PaymentsAPI utilizou SQLite com PVC. A NotificationsAPI corrigida foi publicada como `1.0.1` e apresentou `Application started` e `Bus started`.

### Acessar Services Kubernetes pelo computador

Os Services são `ClusterIP`. Execute cada encaminhamento em um terminal separado, apenas quando necessário:

```powershell
kubectl port-forward svc/users-api 8090:80
kubectl port-forward svc/catalog-api 8091:80
kubectl port-forward svc/payments-api 8092:80
kubectl port-forward svc/notifications-api 8093:80
kubectl port-forward svc/rabbitmq 15675:15672
```

Os encaminhamentos não alteram a comunicação interna dos Pods. O SQL Server e o PaymentsAPI utilizam PVCs (`catalog-sqlserver-data` e `payments-api-data`). Não aumente as réplicas sem revisar persistência e concorrência de acesso aos dados.

## 6. Segurança e solução de problemas

- `.env` é local e ignorado pelo Git; `.env.example` contém apenas valores de exemplo.
- Secrets Kubernetes são criados no deploy e não devem ser versionados. O uso de Secret não garante, por si só, criptografia em repouso; os scripts são voltados ao ambiente acadêmico/local.
- Alterar um Secret ou `.env` **não muda** a senha de um usuário já existente no RabbitMQ persistido. Em caso de `ACCESS_REFUSED`, sincronize credenciais de forma controlada, sem excluir volumes.
- Se houver conflito na porta `5672` do computador, o Compose deste projeto utiliza externamente `5674` e `15674` para coexistir com outro RabbitMQ local.
- Se a NotificationsAPI entrar em `CrashLoopBackOff`, confira a imagem `1.0.1` (a antiga `1.0.0` tinha problema no executável de inicialização).
- Para falhas de inicialização, verifique `docker compose logs <serviço>` ou `kubectl logs deployment/<serviço> --previous` e `kubectl describe pod <nome>`.
- Repositórios Docker Hub privados exigem `imagePullSecrets` no Kubernetes.

## 7. Eventos RabbitMQ — limitações ainda pendentes

**Infraestrutura disponível não é o mesmo que integração ponta a ponta comprovada.** As versões atuais das APIs precisam de revisão dos contratos e consumidores pelo grupo:

1. **CatalogAPI → PaymentsAPI:** CatalogAPI publica `FCG_CatalogAPI.Domain.Events.OrderPlacedCommand` (`UserId`, `GameId`, `Price`); PaymentsAPI espera `Fcg.Contracts.OrderPlacedEvent` (`OrderId`, `UserId`, `GameId`, `Price`). Nome, namespace e esquema diferem.
2. **PaymentsAPI → CatalogAPI:** CatalogAPI consome `FCG_CatalogAPI.Domain.Events.PaymentProcessedEvent`, com `Price` e `ProcessedAtUtc` como `string`, e usa binding manual da exchange `PaymentPublisher:PaymentProcessedEvent`. PaymentsAPI publica `Fcg.Contracts.PaymentProcessedEvent` com `decimal` e `DateTime`. A compatibilidade de tipo e topologia ainda não foi comprovada.
3. **NotificationsAPI:** o código previamente revisado registra `UserCreatedConsumer` e `PaymentProcessedConsumer`, mas não mostrou `cfg.ConfigureEndpoints(context)` nem endpoints explícitos. O log `Bus started` comprova a conexão ao broker, **não** o recebimento de eventos. O contrato de pagamento também utiliza outro namespace.
4. **UsersAPI:** o código revisado utiliza SQL Server, JWT e RabbitMQ e publica `UserCreatedEvent`; sua emissão e recepção por outros serviços ainda não foram testadas ponta a ponta.

Foi validado **isoladamente no Kubernetes** o ciclo `OrderPlacedEvent → PaymentsAPI → PaymentProcessedEvent`, com publicador e consumidor temporários. Isso **não equivale** a um pedido real percorrendo os quatro serviços.

Após a revisão e publicação de novas tags, validar exchanges, filas e bindings no RabbitMQ; realizar pedido real no CatalogAPI; confirmar processamento no PaymentsAPI e consumo dos eventos nos serviços correspondentes. Atualizar as tags no `.env.example`, manifests e scripts conforme necessário.

## 8. Organização e responsabilidades

- **Repositórios de microsserviços:** código-fonte, Dockerfiles, contratos, testes e publicação das imagens.
- **FCG-Orchestration:** Compose, manifestos Kubernetes, scripts, configuração de conexões, Secrets de deploy e instruções de execução.
- Os manifestos Kubernetes permanecem exclusivamente em `FCG-Orchestration/k8s`, sem duplicação nos repositórios individuais.
- A publicação das imagens não é responsabilidade dos scripts deste repositório; o antigo `publish-payments.ps1` não é utilizado.
