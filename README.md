# FCG-Orchestration

**FIAP Cloud Games (FCG) — Tech Challenge | Fase 2**

Repositório responsável pela configuração, inicialização e orquestração dos microsserviços da plataforma FIAP Cloud Games.

A solução utiliza **Docker, Docker Compose e Kubernetes** para executar os serviços, gerenciar configurações, disponibilizar a infraestrutura e garantir a comunicação entre os componentes da aplicação.

## 1. Visão geral

O FCG-Orchestration centraliza a infraestrutura necessária para executar os quatro microsserviços da plataforma:

| Microsserviço | Responsabilidade |
|---|---|
| **UsersAPI** | Gerenciamento de usuários, autenticação e informações de cadastro. |
| **CatalogAPI** | Gerenciamento do catálogo de jogos, compras e biblioteca dos usuários. |
| **PaymentsAPI** | Processamento de pagamentos, aprovação ou rejeição das transações. |
| **NotificationsAPI** | Processamento de eventos e envio simulado de notificações. |

A comunicação entre os microsserviços ocorre por meio de eventos assíncronos utilizando o **RabbitMQ**.

### Tecnologias utilizadas

- .NET 8
- Docker e Docker Compose
- Kubernetes
- RabbitMQ
- SQL Server
- SQLite
- PowerShell

## 2. Arquitetura da solução

A plataforma utiliza uma arquitetura de microsserviços com comunicação assíncrona e responsabilidades independentes.

O Kubernetes é responsável pela orquestração dos serviços, utilizando os seguintes recursos:

| Recurso | Responsabilidade |
|---|---|
| **Deployments** | Gerenciamento dos Pods e das réplicas das aplicações. |
| **Services** | Comunicação e descoberta dos serviços no cluster. |
| **ConfigMaps** | Armazenamento das configurações não sensíveis. |
| **Secrets** | Armazenamento das credenciais e informações sensíveis. |
| **PersistentVolumeClaims (PVCs)** | Persistência dos dados necessários à aplicação. |
| **Liveness e Readiness Probes** | Verificação da integridade e disponibilidade dos serviços. |

Os manifestos Kubernetes são mantidos de forma centralizada no diretório `/k8s` deste repositório.

### Comunicação entre microsserviços

O fluxo principal de comunicação ocorre da seguinte forma:

1. A **UsersAPI** gerencia usuários e publica eventos relacionados ao cadastro.
2. A **CatalogAPI** gerencia os jogos e inicia o fluxo de compra.
3. A **PaymentsAPI** recebe o evento `OrderPlacedEvent` e processa o pagamento.
4. Após o processamento, a PaymentsAPI publica o evento `PaymentProcessedEvent`, informando o resultado da transação.
5. A **CatalogAPI** e a **NotificationsAPI** recebem os eventos correspondentes e executam suas responsabilidades.

O RabbitMQ atua como intermediário da comunicação, permitindo que os microsserviços processem eventos de maneira desacoplada.

## 3. Pré-requisitos

Para executar o ambiente localmente, é necessário ter instalado:

- **Docker Desktop**, com o Docker Engine em execução.
- **Kubernetes**, habilitado no Docker Desktop.
- **Git**, para clonar o repositório.
- **Windows PowerShell**, para executar os scripts de configuração e deploy.

Antes de iniciar, verifique se o Docker Desktop está aberto e se o Kubernetes está habilitado e disponível.

## 4. Como executar o projeto

Todos os comandos devem ser executados no **PowerShell**, a partir da pasta raiz do repositório `FCG-Orchestration`.

### Passo 1 — Clonar o repositório

Faça o clone do repositório FCG-Orchestration:

```powershell
git clone <URL_DO_REPOSITORIO_FCG_ORCHESTRATION>
```

Acesse a pasta:

```powershell
cd FCG-Orchestration
```

### Passo 2 — Configurar o ambiente

Execute o script de configuração:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup.ps1
```

O script prepara as configurações necessárias para executar a aplicação, incluindo a geração do arquivo `.env` com as credenciais do ambiente.

**Importante:** o arquivo `.env` contém informações sensíveis e não deve ser versionado no GitHub.

Em ambientes já inicializados, evite regenerar credenciais sem verificar as configurações e os volumes persistentes.

### Passo 3 — Subir os containers Docker

Execute:

```powershell
docker compose up -d
```

O Docker Compose inicializa os serviços e a infraestrutura definidos no arquivo de composição.

O parâmetro `-d` permite que os containers sejam executados em segundo plano.

Para verificar o estado dos containers:

```powershell
docker compose ps
```

### Passo 4 — Executar o deploy no Kubernetes

Com a infraestrutura inicializada e o Kubernetes disponível, execute:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-local.ps1
```

O script realiza o deploy local dos recursos Kubernetes definidos no projeto.

A execução utiliza os manifestos centralizados para configurar e disponibilizar os recursos necessários à aplicação.

### Passo 5 — Validar o ambiente

Após a execução do deploy, utilize:

```powershell
kubectl get pods
```

Esse comando permite verificar os Pods e seus respectivos estados.

Para consultar os serviços:

```powershell
kubectl get services
```

Para consultar os Deployments:

```powershell
kubectl get deployments
```

Para verificar todos os recursos principais:

```powershell
kubectl get all
```

**Resultado esperado:** os Pods devem estar em execução e disponíveis, respeitando as condições de inicialização e as verificações de saúde configuradas.

## 5. Como visualizar os logs

Os logs permitem acompanhar a inicialização dos serviços, o processamento das requisições e a comunicação entre os microsserviços.

### Logs pelo Docker Compose

Execute os comandos na pasta raiz do repositório.

**CatalogAPI**

```powershell
docker compose logs -f --tail=50 catalog-api
```

**UsersAPI**

```powershell
docker compose logs -f --tail=50 users-api
```

**NotificationsAPI**

```powershell
docker compose logs -f --tail=50 notifications-api
```

**PaymentsAPI**

```powershell
docker compose logs -f --tail=50 payments-api
```

O parâmetro `-f` acompanha os logs em tempo real, enquanto `--tail=50` apresenta inicialmente as últimas 50 linhas.

Para interromper a visualização, pressione `Ctrl + C`.

### Logs pelo Kubernetes

Para acompanhar diretamente os logs dos microsserviços executados no Kubernetes, utilize:

**CatalogAPI**

```powershell
kubectl logs -f deployment/catalog-api --tail=50
```

**UsersAPI**

```powershell
kubectl logs -f deployment/users-api --tail=50
```

**NotificationsAPI**

```powershell
kubectl logs -f deployment/notifications-api --tail=50
```

**PaymentsAPI**

```powershell
kubectl logs -f deployment/payments-api --tail=50
```

Esses comandos consideram os nomes dos Deployments e o namespace padrão configurado no contexto Kubernetes.

Para consultar eventos e informações detalhadas de um Pod:

```powershell
kubectl describe pod <NOME_DO_POD>
```

## 6. Verificação do funcionamento

Após inicializar o ambiente, é possível acompanhar o funcionamento da aplicação por meio dos logs e do estado dos recursos Kubernetes.

### Verificar Pods

```powershell
kubectl get pods
```

### Verificar os serviços

```powershell
kubectl get services
```

### Verificar os containers Docker

```powershell
docker compose ps
```

### Acompanhar o processamento dos pagamentos

```powershell
kubectl logs -f deployment/payments-api --tail=50
```

Nos logs da PaymentsAPI, é possível acompanhar eventos relacionados a:

- Recebimento do `OrderPlacedEvent`.
- Processamento do pagamento.
- Resultado `Approved` ou `Rejected`.
- Publicação do `PaymentProcessedEvent`.
- Falhas de processamento ou comunicação.

### Acompanhar o processamento no Catalog

```powershell
kubectl logs -f deployment/catalog-api --tail=50
```

Permite verificar o recebimento dos eventos de pagamento e as atualizações correspondentes no catálogo ou na biblioteca do usuário.

### Acompanhar as notificações

```powershell
kubectl logs -f deployment/notifications-api --tail=50
```

Permite verificar o consumo dos eventos e o processamento das notificações simuladas.

## 7. Configurações e segurança

A solução utiliza mecanismos de configuração e segurança adequados à execução em containers e no Kubernetes.

**Arquivo `.env`**

Responsável por disponibilizar as variáveis de ambiente necessárias à execução local dos serviços.

**ConfigMaps**

Utilizados para armazenar configurações não sensíveis, como endereços de serviços e parâmetros de integração.

**Secrets**

Utilizados para armazenar credenciais e informações sensíveis, como senhas e strings de conexão.

**Persistência**

Os recursos de persistência permitem armazenar os dados necessários à operação dos serviços, respeitando a configuração dos volumes do ambiente.

As credenciais reais não devem ser incluídas no código-fonte ou no README.

## 8. Encerramento do ambiente

Para interromper os containers gerenciados pelo Docker Compose:

```powershell
docker compose down
```

O comando interrompe e remove os containers e a rede criados pelo Compose, sem remover automaticamente os volumes nomeados.

**Atenção:** esse comando não remove os Deployments e Pods do Kubernetes.

A remoção dos recursos Kubernetes deve ser realizada separadamente, conforme os manifestos aplicados no cluster.

Evite remover volumes persistentes, Secrets ou recursos do Kubernetes indiscriminadamente, pois isso pode comprometer os dados e as configurações do ambiente.

## 9. Estrutura do repositório

Os principais componentes da organização do repositório são:

```text
FCG-Orchestration/
│
├── k8s/
│   └── Manifestos Kubernetes
│
├── scripts/
│   ├── setup.ps1
│   └── deploy-local.ps1
│
├── docker-compose.yml
├── .env
└── README.md
```

O arquivo `.env` é gerado localmente e não deve ser incluído no controle de versão.

## 10. Resumo dos comandos

### Inicialização completa

```powershell
# Configurar o ambiente
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup.ps1

# Iniciar os containers
docker compose up -d

# Executar o deploy Kubernetes
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-local.ps1
```

### Verificar o ambiente

```powershell
docker compose ps
kubectl get pods
kubectl get services
kubectl get deployments
```

### Visualizar logs Docker

```powershell
docker compose logs -f --tail=50 catalog-api
docker compose logs -f --tail=50 users-api
docker compose logs -f --tail=50 notifications-api
docker compose logs -f --tail=50 payments-api
```

### Visualizar logs Kubernetes

```powershell
kubectl logs -f deployment/catalog-api --tail=50
kubectl logs -f deployment/users-api --tail=50
kubectl logs -f deployment/notifications-api --tail=50
kubectl logs -f deployment/payments-api --tail=50
```

---

**FIAP Cloud Games — Tech Challenge Fase 2**

Repositório de orquestração e infraestrutura dos microsserviços da plataforma FCG.