Projeto de Integração, Consolidação e Arquitetura de Dados - PMWEB
Objetivo
Este projeto implementa uma solução completa de dados abordando desde processos de ETL (Extract, Transform and Load) com SQL Server até estratégias avançadas de Arquitetura, Governança e processamento em tempo real (Event-Driven). O repositório reflete as entregas da Avaliação Técnica - Data Services, dividida em duas grandes frentes operacionais e estratégicas.

Parte 1: Engenharia de Dados e Analytics (Data Analyst)
Esta etapa abrange a importação de arquivos CSV, modelagem de dados, tratamento, carga para tabelas de produção e geração de análises de negócio.

1. Arquitetura da Solução
O fluxo de processamento segue as etapas abaixo:

Criação da base de dados e estruturas de staging.

Importação dos arquivos CSV para tabelas temporárias.

Execução da procedure de integração (higienização, conversão de tipos e carga).

Carga nas tabelas finais via instrução MERGE.

Registro de auditoria e logs de execução.

Execução das consultas analíticas.

2. Modelo de Dados (DER)

'''

mermaid
erDiagramCLIENTES ||--o{ PEDIDOS : "realiza"

    CLIENTES {
        int ID PK
        varchar EMAIL
        varchar NOME
        date DATA_NASCIMENTO
        varchar CIDADE
        char UF
        bit PERMISSAO_RECEBE_EMAIL
    }

    PEDIDOS {
        int ID_PEDIDO
        int ID_PRODUTO
        int ID_CLIENTE FK
        varchar DEPARTAMENTO
        int QUANTIDADE
        decimal VALOR_UNITARIO
        int PARCELAS
        date DATA_PEDIDO
        varchar MEIO_PAGAMENTO
        varchar STATUS_PAGAMENTO
    }

    LOG_RODADA {
        int ID_LOG PK
        datetime DATA_INICIO
        datetime DATA_FIM
        int QTD_CLIENTES_PROCESSADOS
        int QTD_PEDIDOS_PROCESSADOS
        varchar STATUS_RODADA
        varchar MENSAGEM
    }

    STG_CLIENTES {
        varchar ID
        varchar EMAIL
        varchar NOME
        varchar DT_NASC
        varchar CIDADE
        varchar ESTADO
        varchar RECEBE_EMAIL
    }

    STG_PEDIDOS {
        varchar COD_CLIENTE
        varchar COD_PEDIDO
        varchar CODIGO_PRODUTO
        varchar DEPTO
        varchar QUANTIDADE
        varchar VALOR_UNITARIO
        varchar QTD_PARCELAS
        varchar DT_PEDIDO
        varchar MEIO_PAGTO
        varchar STATUS_PAGAMENTO
    }
    '''
3.Estrutura de Arquivos da Parte 1
Arquivo,Descrição
01_ddl_e_staging.sql,"Criação do banco de dados e tabelas de produção, staging e log"
02_procedure_integracao.sql,Procedure responsável pelo processo de integração e carga
03_bulk_insert.sql,Importação dos arquivos CSV para staging
04_consolidacoes_item4.sql,Consultas analíticas e indicadores de negócio


4. Processo de Carga (ETL)
Importação (Bulk Insert): Os dados são inicialmente movidos para tabelas de Staging (STG_CLIENTES, STG_PEDIDOS).

Tratamento e Transformação (SP_INTEGRACAO_DADOS): Realiza remoção de espaços em branco, padronização de UF, conversão de datas/moedas, validação de registros nulos e operações transacionais seguras (COMMIT/ROLLBACK).

Controle e Logging: Cada execução grava um histórico na tabela LOG_RODADA, garantindo rastreabilidade do tempo de execução e volumetria processada.

5. Consultas Analíticas Implementadas
Pedidos Parcelados por Cliente: Agrupados por semestre e ano (excluindo cancelados).

Ticket Médio por Cliente: Agrupamento por ano e mês.

Intervalo Médio Entre Compras: Em dias, utilizando a função LAG().

Tiers de Clientes: Classificação de gasto mensal (Básico, Prata, Ouro, Super).

Comparativo YoY (2019 x 2020): Variação percentual de vendas para departamentos específicos.
  
Parte 2: Sênior & Especialista (Arquitetura, Engenharia Escalável e Negócio)
Esta seção aborda desafios arquiteturais para sistemas escaláveis, observabilidade, performance tuning e integrações modernas.

1. Engenharia de Dados & Observabilidade (High Complexity)
Arquivo: 01_eng_dados_observ.sql

Data Lineage & Audit: Implementação de arquitetura de logs capturando Trace ID único por execução, volumetria de entrada vs. saída e tempo de processamento por etapa (ETL_AUDIT_LOG).

Resiliência (Fault Tolerance): Pipeline preparado para retomas automáticas (Checkpointing). Em caso de falha de lote massivo, a tabela ETL_CHECKPOINT armazena o último ID processado para continuidade segura.

Sanitização Avançada: Tratamento em T-SQL para padronizar nomes (Proper Case), validar e-mails (Regex) e aplicar lógicas de preenchimento inteligente em campos nulos críticos.

2. Inteligência Aplicada (SQL & Analytics)
Arquivo: 02_kpis_avancados.sql
Scripts otimizados empregando Window Functions e CTEs para geração de KPIs avançados:

Next Best Action (NBA): Cruzamento do departamento favorito do cliente com os produtos de maior giro da categoria para recomendação preditiva.

LTV (Lifetime Value): Cálculo do valor histórico gerado pelo cliente desde a primeira transação, aplicando agrupamento distributivo em decis (NTILE(10)).

Detecção de Anomalias: Identificação de pedidos outliers, sinalizando valores unitários que ultrapassam 3 desvios padrão acima da média da respectiva categoria (Z-Score).

3. Arquitetura & Governança (Desafio Teórico)
SCD Tipo 4 (Histórico Rápido de Crédito): Para evitar inflar a dimensão de clientes com atributos altamente voláteis (Score/Status de Crédito), implementa-se uma Mini-Dimension (Dim_Perfil_Credito). A tabela Fato transacional grava a Surrogate Key do perfil ativo no momento da compra, isolando as mudanças sem sobrecarregar processamento ou armazenamento.

Performance Tuning para 100M+ Linhas: Otimização de joins para dashboards em tempo real utilizando índices colunares (Clustered Columnstore Index), particionamento de tabelas por data, eliminação estrita de conversões implícitas (mantendo SARGable predicates) e materialização via Indexed Views para os agregados principais.

4. Case Especialista: Estratégia CRM (Salesforce / Data Cloud)
Golden Record (Identidade Única): Em caso de múltiplos sistemas, utiliza-se regras de correspondência (Matching Rules - Exato/Fuzzy) combinadas a regras de sobrevivência (Survivorship Rules - Recência/Prioridade da Fonte) para criar o Unified Individual ID. O dado retém o Data Lineage de todos os IDs de origem.

Mascaramento de PII: Implementação de Dynamic Data Masking (DDM) e Hashing Determinístico (SHA-256) nas visualizações de Analytics, mantendo a utilidade do dado para modelagem estatística. Para automações de Marketing, ferramentas disparam integrações que revertem os tokens com permissões estritas para ativação.

5. Desafios de Arquitetura Elite
Zero-Copy Integration & Data Sharing: Abandono de processos morosos de ETL/FTP físico em prol do compartilhamento direto pela camada semântica (ex: Snowflake Data Sharing, Delta Sharing). Cria-se Secure Views protegidas por Row-Level Security (RLS), onde o parceiro externo consome os dados em tempo real arcando com seu próprio compute (Reader Accounts).

Event-Driven Data Processing (< 5 Segundos):
Arquitetura reativa baseada em eventos. A mudança (novo pedido) é capturada via Change Data Capture (CDC) com Debezium no Transaction Log do banco. O evento é lançado em um tópico do Apache Kafka, processado por Apache Flink (recalculando Tiers) e disparado via Webhooks/Lambda direto para a API do CRM, garantindo escalabilidade e baixíssima latência.




