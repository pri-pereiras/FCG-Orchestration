# FCG-Orchestration — Tech Challenge Fase 2

Quinto repositório, dedicado exclusivamente à **orquestração e infraestrutura** da FIAP Cloud Games.

## Organização dos cinco repositórios

Todos devem ser clonados como pastas **irmãs**:

```text
FCG/
├── UsersAPI/                   # futuro: repositório separado
├── CatalogAPI/                 # futuro: repositório separado
├── PaymentsAPI/                # repositório do serviço, com seu Dockerfile e k8s/
├── NotificationsAPI/           # futuro: repositório separado
└── FCG-Orchestration/          # ESTE repositório
    ├── docker-compose.yml
    ├── .env.example
    ├── k8s/rabbitmq/rabbitmq.yaml
    └── scripts/deploy-local.sh
```

## Docker Compose (etapa atual)

O compose **já executa o RabbitMQ e o PaymentsAPI**, usando o `Dockerfile` mantido no repositório da API. Os outros três serviços serão acrescentados quando forem implementados. Portanto, **a aplicação completa ainda não está pronta para `docker compose up`**.

```bash
cd FCG-Orchestration
cp .env.example .env
# editar .env e definir credenciais locais
# Windows PowerShell: Copy-Item .env.example .env
docker compose up --build -d
docker compose ps
docker compose logs -f payments-api
```

- API pagamentos: http://localhost:8082/swagger
- RabbitMQ management: http://localhost:15672 (credenciais no `.env`)
- Health check: http://localhost:8082/health

**Contratos compartilhados:** Catalog publica `OrderPlacedEvent`, Payments consome e publica `PaymentProcessedEvent`; Catalog e Notifications devem consumi-lo em **filas diferentes**. Padronizar tipos e namespaces em todos os serviços.

## Kubernetes local

- Cada microserviço conserva `Dockerfile` e `k8s/` próprios (exigido pelo enunciado).
- Este repositório guarda a implantação do broker e centraliza o comando de deploy.
- Aplique primeiro a infraestrutura e depois os manifests de cada serviço. Em Bash:

```bash
./scripts/deploy-local.sh
kubectl get deployments,services,pods
```

- Se necessário, construa/carregue as imagens localmente no seu cluster (`payments-api:local` é o nome usado no deployment de PaymentsAPI).
- O exemplo de Secret do PaymentsAPI possui `RabbitMq__Username=payments` e senha `CHANGE_ME`. **Antes do deploy**, configure-o com as mesmas credenciais criadas para o RabbitMQ; não versionar senhas reais.
- Em ambiente de estudo, os exemplos no diretório `k8s/` contêm valores fictícios: **não usar em produção**.
- A persistência do RabbitMQ nesta versão Kubernetes é efêmera. Para produção, usar StatefulSet e volume persistente, autenticação/TLS e credenciais gerenciadas.

## Próximos incrementos

1. Adicionar ao Compose os três novos serviços e suas dependências, sem copiar o código das APIs.
2. Completar a configuração dos consumidores no CatalogAPI e NotificationsAPI.
3. Padronizar Secrets e ConfigMaps por serviço e automatizar deploy do cluster local.
4. Validar `docker compose up --build`, fluxo ponta a ponta e `kubectl get pods`.

> Esta entrega é um **esqueleto de orquestração operacional para PaymentsAPI + RabbitMQ**, não uma implementação fictícia das outras três APIs.
