-- =========================================================================
-- ARQUITETURA DE CONTROLE E AUDITORIA
-- =========================================================================

-- Tabela de Logs (Data Lineage & Audit)
CREATE TABLE ETL_AUDIT_LOG (
    LogID INT IDENTITY(1,1) PRIMARY KEY,
    TraceID UNIQUEIDENTIFIER, -- Rastreador único por execução
    TabelaAlvo VARCHAR(100),
    Etapa VARCHAR(100),
    DataInicio DATETIME,
    DataFim DATETIME,
    DuracaoSegundos AS DATEDIFF(SECOND, DataInicio, DataFim),
    LinhasLidas INT,
    LinhasEscritas INT,
    StatusProcesso VARCHAR(50),
    MensagemErro VARCHAR(MAX)
);

-- Tabela de Checkpoint (Resiliência)
CREATE TABLE ETL_CHECKPOINT (
    TabelaAlvo VARCHAR(100) PRIMARY KEY,
    Ultimo_ID_Processado INT,
    DataUltimoProcessamento DATETIME
);
INSERT INTO ETL_CHECKPOINT (TabelaAlvo, Ultimo_ID_Processado, DataUltimoProcessamento) 
VALUES ('CLIENTES', 0, GETDATE()), ('PEDIDOS', 0, GETDATE());

-- =========================================================================
-- Tabela de Staging Adaptada para Checkpointing
-- =========================================================================
CREATE TABLE STG_CLIENTES (
    ID_STG INT IDENTITY(1,1) PRIMARY KEY, -- Chave para o Checkpoint
    ID VARCHAR(50),
    EMAIL VARCHAR(255),
    NOME VARCHAR(255),
    DT_NASC VARCHAR(50),
    CIDADE VARCHAR(100),
    ESTADO VARCHAR(50),
    RECEBE_EMAIL VARCHAR(50)
);

-- =========================================================================
-- PIPELINE RESILIENTE COM PYTHON INTEGRADO (SQL Server ML Services)
-- =========================================================================

CREATE OR ALTER PROCEDURE SP_ETL_SENIOR_CLIENTES_PYTHON
AS
BEGIN
    SET NOCOUNT ON;

    -- Variáveis de Controle e Auditoria
    DECLARE @TraceID UNIQUEIDENTIFIER = NEWID();
    DECLARE @BatchSize INT = 50000;
    DECLARE @UltimoID INT;
    DECLARE @MaxID INT;
    DECLARE @LimiteBatch INT;
    DECLARE @LinhasProcessadas INT = 0;
    DECLARE @InicioEtapa DATETIME;
    
    -- Recupera o Checkpoint
    SELECT @UltimoID = Ultimo_ID_Processado FROM ETL_CHECKPOINT WHERE TabelaAlvo = 'CLIENTES';
    SELECT @MaxID = ISNULL(MAX(ID_STG), 0) FROM STG_CLIENTES;

    -- Query de extração dinâmica que será passada para o motor do Python
    DECLARE @ExtractQuery NVARCHAR(MAX) = N'
        SELECT 
            CAST(ID AS INT) AS ID, 
            EMAIL, 
            NOME, 
            DT_NASC, 
            CIDADE, 
            ESTADO, 
            RECEBE_EMAIL 
        FROM STG_CLIENTES 
        WHERE ID_STG > @P_UltimoID AND ID_STG <= @P_LimiteBatch
    ';

    -- Início do Loop de Lotes
    WHILE @UltimoID < @MaxID
    BEGIN
        SET @InicioEtapa = GETDATE();
        SET @LimiteBatch = @UltimoID + @BatchSize;

        BEGIN TRY
            BEGIN TRANSACTION;

            -- Inserção na Tabela Final consumindo o output do script Python
            INSERT INTO CLIENTES (ID, EMAIL, NOME, DATA_NASCIMENTO, CIDADE, UF, PERMISSAO_RECEBE_EMAIL)
            EXEC sp_execute_external_script
                @language = N'Python',
                @script = N'
import pandas as pd
import re

# Função Regex para validar e-mails
def valida_email(email):
    if pd.isna(email) or email == "":
        return "email_invalido@sistema.com"
    # Regex padrão da indústria para validação de formato
    if re.match(r"^[\w\.-]+@[\w\.-]+\.\w+$", str(email)):
        return str(email).lower().strip()
    return "email_invalido@sistema.com"

# InputDataSet é a variável padrão que recebe o resultado da query SQL
df = InputDataSet

# 1. Proper Case (Capitalização correta de Nomes)
df["NOME"] = df["NOME"].str.title()

# 2. Sanitização de E-mails via Regex
df["EMAIL"] = df["EMAIL"].apply(valida_email)

# 3. Conversão de Datas (Coerção de erros para NaT)
df["DT_NASC"] = pd.to_datetime(df["DT_NASC"], format="%d/%m/%Y", errors="coerce").dt.strftime("%Y-%m-%d")

# 4. Tratamento lógico de Nulos (Abordagem limpa com fillna)
df["CIDADE"] = df["CIDADE"].fillna("CIDADE NÃO INFORMADA")
df["ESTADO"] = df["ESTADO"].fillna("NA").str.slice(0, 2)

# 5. Tratamento de booleanos
df["RECEBE_EMAIL"] = df["RECEBE_EMAIL"].fillna(0).astype(int)

# O script retorna o DataFrame transformado para o SQL Server
OutputDataSet = df
',
                @input_data_1 = @ExtractQuery,
                @params = N'@P_UltimoID INT, @P_LimiteBatch INT',
                @P_UltimoID = @UltimoID,
                @P_LimiteBatch = @LimiteBatch
            WITH RESULT SETS (
                (
                    ID INT, 
                    EMAIL VARCHAR(255), 
                    NOME VARCHAR(255), 
                    DATA_NASCIMENTO DATE, 
                    CIDADE VARCHAR(100), 
                    UF CHAR(2), 
                    PERMISSAO_RECEBE_EMAIL BIT
                )
            );

            SET @LinhasProcessadas = @@ROWCOUNT;

            -- Atualiza o ponteiro de Checkpoint
            SET @UltimoID = @LimiteBatch;
            
            UPDATE ETL_CHECKPOINT 
            SET Ultimo_ID_Processado = @UltimoID, DataUltimoProcessamento = GETDATE()
            WHERE TabelaAlvo = 'CLIENTES';

            COMMIT TRANSACTION;

            -- Log de Sucesso do Lote
            INSERT INTO ETL_AUDIT_LOG (TraceID, TabelaAlvo, Etapa, DataInicio, DataFim, LinhasLidas, LinhasEscritas, StatusProcesso)
            VALUES (@TraceID, 'CLIENTES', 'Batch com Python', @InicioEtapa, GETDATE(), @BatchSize, @LinhasProcessadas, 'SUCESSO');

        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

            -- Log de Falha
            INSERT INTO ETL_AUDIT_LOG (TraceID, TabelaAlvo, Etapa, DataInicio, DataFim, StatusProcesso, MensagemErro)
            VALUES (@TraceID, 'CLIENTES', 'Falha no Batch Python', @InicioEtapa, GETDATE(), 'ERRO', ERROR_MESSAGE());
            
            BREAK; 
        END CATCH
    END

    IF @UltimoID >= @MaxID
    BEGIN
        UPDATE ETL_CHECKPOINT SET Ultimo_ID_Processado = 0 WHERE TabelaAlvo = 'CLIENTES';
        TRUNCATE TABLE STG_CLIENTES;
    END
END;