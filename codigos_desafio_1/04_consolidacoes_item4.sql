


/****** Quantidade de pedidos por cliente:  ○ Por semestre de cada ano, apenas de clientes que parcelaram   ******/
SELECT 
    ID_CLIENTE,
    YEAR(DATA_PEDIDO) AS ANO,
    CASE 
        WHEN MONTH(DATA_PEDIDO) <= 6 THEN 1 
        ELSE 2 
    END AS SEMESTRE,
    COUNT(DISTINCT ID_PEDIDO) AS QTD_PEDIDOS_PARCELADOS
FROM PEDIDOS
WHERE PARCELAS > 1 
  AND STATUS_PAGAMENTO <> 'CANCELADO'
GROUP BY 
    ID_CLIENTE,
    YEAR(DATA_PEDIDO),
    CASE 
        WHEN MONTH(DATA_PEDIDO) <= 6 THEN 1 
        ELSE 2 
    END
ORDER BY 
    ID_CLIENTE, ANO, SEMESTRE;

/******  Ticket médio de cada cliente  ○ Por ano e mês   ******/ 

WITH ValorPorPedido AS (
    SELECT 
        ID_CLIENTE,
        ID_PEDIDO,
        YEAR(DATA_PEDIDO) AS ANO,
        MONTH(DATA_PEDIDO) AS MES,
        SUM(QUANTIDADE * VALOR_UNITARIO) AS TOTAL_DO_PEDIDO
    FROM PEDIDOS
    WHERE STATUS_PAGAMENTO <> 'CANCELADO'
    GROUP BY 
        ID_CLIENTE, ID_PEDIDO, YEAR(DATA_PEDIDO), MONTH(DATA_PEDIDO)
)
SELECT 
    ID_CLIENTE,
    ANO,
    MES,
    AVG(TOTAL_DO_PEDIDO) AS TICKET_MEDIO
FROM ValorPorPedido
GROUP BY 
    ID_CLIENTE, ANO, MES
ORDER BY 
    ID_CLIENTE, ANO, MES;

/******  ● Intervalo médio entre as compras de cada cliente  ○ Por ano    ******/ 

    WITH PedidosUnicos AS (
    -- Pegamos a data de cada pedido (ignorando múltiplas linhas de itens do mesmo pedido)
    SELECT DISTINCT 
        ID_CLIENTE, 
        ID_PEDIDO, 
        DATA_PEDIDO,
        YEAR(DATA_PEDIDO) AS ANO
    FROM PEDIDOS
    WHERE STATUS_PAGAMENTO <> 'CANCELADO'
),
CalculoIntervalo AS (
    SELECT 
        ID_CLIENTE,
        ANO,
        DATA_PEDIDO,
        -- LAG pega a data do pedido imediatamente anterior do mesmo cliente
        LAG(DATA_PEDIDO) OVER(PARTITION BY ID_CLIENTE ORDER BY DATA_PEDIDO) AS DATA_COMPRA_ANTERIOR
    FROM PedidosUnicos
)
SELECT 
    ID_CLIENTE,
    ANO,
    AVG(DATEDIFF(DAY, DATA_COMPRA_ANTERIOR, DATA_PEDIDO)) AS INTERVALO_MEDIO_DIAS
FROM CalculoIntervalo
WHERE DATA_COMPRA_ANTERIOR IS NOT NULL
  AND YEAR(DATA_COMPRA_ANTERIOR) = ANO -- Garante que o intervalo é do mesmo ano
GROUP BY 
    ID_CLIENTE, ANO
ORDER BY 
    ID_CLIENTE, ANO;

/******   Classificação de cada cliente em tiers, de acordo com o seu valor de compras mensal     ******/ 

WITH GastosMensais AS (
    SELECT 
        SUM(QUANTIDADE * VALOR_UNITARIO) AS VALOR_TOTAL_MENSAL
    FROM PEDIDOS
    WHERE STATUS_PAGAMENTO <> 'CANCELADO'
    GROUP BY 
        ID_CLIENTE, YEAR(DATA_PEDIDO), MONTH(DATA_PEDIDO)
),
ClassificacaoTiers AS (
    SELECT 
        CASE 
            WHEN VALOR_TOTAL_MENSAL <= 1000 THEN 'Básico'
            WHEN VALOR_TOTAL_MENSAL <= 2000 THEN 'Prata'
            WHEN VALOR_TOTAL_MENSAL <= 5000 THEN 'Ouro'
            ELSE 'Super'
        END AS FAIXA
    FROM GastosMensais
)
SELECT 
    FAIXA,
    COUNT(*) AS QUANTIDADE_REGISTROS_INCLUIDOS
FROM ClassificacaoTiers
GROUP BY 
    FAIXA
ORDER BY 
    CASE FAIXA 
        WHEN 'Básico' THEN 1 
        WHEN 'Prata' THEN 2 
        WHEN 'Ouro' THEN 3 
        WHEN 'Super' THEN 4 
    END;

/******    Comparativo percentual entre valores totais de compras efetivadas, em 2019 e 2020, para os segmentos de som e papelaria     ******/ 

WITH TotalPorAno AS (
    SELECT 
        DEPARTAMENTO,
        YEAR(DATA_PEDIDO) AS ANO,
        SUM(QUANTIDADE * VALOR_UNITARIO) AS VALOR_VENDIDO
    FROM PEDIDOS
    WHERE STATUS_PAGAMENTO <> 'CANCELADO'
      AND YEAR(DATA_PEDIDO) IN (2019, 2020)
      AND DEPARTAMENTO IN ('SOM', 'PAPELARIA')
    GROUP BY 
        DEPARTAMENTO, YEAR(DATA_PEDIDO)
),
PivotAnos AS (
    -- Pivota os dados para ter colunas de 2019 e 2020 na mesma linha
    SELECT 
        DEPARTAMENTO,
        SUM(CASE WHEN ANO = 2019 THEN VALOR_VENDIDO ELSE 0 END) AS TOTAL_2019,
        SUM(CASE WHEN ANO = 2020 THEN VALOR_VENDIDO ELSE 0 END) AS TOTAL_2020
    FROM TotalPorAno
    GROUP BY DEPARTAMENTO
)
SELECT 
    DEPARTAMENTO,
    TOTAL_2019,
    TOTAL_2020,
    -- Cálculo Percentual evitando erro de divisão por zero
    CASE 
        WHEN TOTAL_2019 = 0 AND TOTAL_2020 > 0 THEN 100.00
        WHEN TOTAL_2019 = 0 AND TOTAL_2020 = 0 THEN 0.00
        ELSE CAST(((TOTAL_2020 - TOTAL_2019) / TOTAL_2019) * 100 AS DECIMAL(10,2))
    END AS VARIACAO_PERCENTUAL
FROM PivotAnos;