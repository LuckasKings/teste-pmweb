WITH ClienteDeptoFavorito AS (
    -- Descobre o departamento onde o cliente fez mais pedidos
    SELECT 
        ID_CLIENTE, 
        DEPARTAMENTO,
        ROW_NUMBER() OVER(PARTITION BY ID_CLIENTE ORDER BY COUNT(ID_PEDIDO) DESC) as RankDepto
    FROM PEDIDOS
    WHERE STATUS_PAGAMENTO <> 'CANCELADO'
    GROUP BY ID_CLIENTE, DEPARTAMENTO
),
ProdutoTopPorDepto AS (
    -- Descobre o produto mais vendido em cada departamento (comportamento da categoria)
    SELECT 
        DEPARTAMENTO, 
        ID_PRODUTO,
        ROW_NUMBER() OVER(PARTITION BY DEPARTAMENTO ORDER BY COUNT(ID_PEDIDO) DESC) as RankProduto
    FROM PEDIDOS
    WHERE STATUS_PAGAMENTO <> 'CANCELADO'
    GROUP BY DEPARTAMENTO, ID_PRODUTO
)
-- Gera a Recomendação NBA (Next Best Action)
SELECT 
    C.ID_CLIENTE,
    C.DEPARTAMENTO AS Depto_Maior_Afinidade,
    P.ID_PRODUTO AS Produto_Recomendado_NBA
FROM ClienteDeptoFavorito C
INNER JOIN ProdutoTopPorDepto P ON C.DEPARTAMENTO = P.DEPARTAMENTO
WHERE C.RankDepto = 1  -- Pega apenas o depto favorito do cliente
  AND P.RankProduto = 1; -- Pega apenas o produto mais vendido desse depto


  WITH LifetimeValue AS (
    -- Calcula o LTV e encontra a data da primeira compra de cada cliente
    SELECT 
        ID_CLIENTE,
        MIN(DATA_PEDIDO) AS Data_Primeira_Transacao,
        SUM(QUANTIDADE * VALOR_UNITARIO) AS LTV_Total
    FROM PEDIDOS
    WHERE STATUS_PAGAMENTO <> 'CANCELADO'
    GROUP BY ID_CLIENTE
)
SELECT 
    ID_CLIENTE,
    Data_Primeira_Transacao,
    LTV_Total,
    -- NTILE(10) distribui os clientes em 10 decis (1 = Top 10% de clientes, 10 = Bottom 10%)
    NTILE(10) OVER(ORDER BY LTV_Total DESC) AS Decil_Faturamento
FROM LifetimeValue
ORDER BY 
    Decil_Faturamento ASC, 
    LTV_Total DESC;

    WITH CalculoEstatisticas AS (
    SELECT 
        ID_PEDIDO,
        ID_CLIENTE,
        ID_PRODUTO,
        DEPARTAMENTO,
        VALOR_UNITARIO,
        -- Calcula a média e o desvio padrão particionado pela categoria
        AVG(VALOR_UNITARIO) OVER(PARTITION BY DEPARTAMENTO) AS Media_Categoria,
        STDEV(VALOR_UNITARIO) OVER(PARTITION BY DEPARTAMENTO) AS Desvio_Padrao_Categoria
    FROM PEDIDOS
    WHERE STATUS_PAGAMENTO <> 'CANCELADO'
),
CalculoZScore AS (
    SELECT 
        ID_PEDIDO,
        ID_CLIENTE,
        ID_PRODUTO,
        DEPARTAMENTO,
        VALOR_UNITARIO,
        Media_Categoria,
        Desvio_Padrao_Categoria,
        -- Fórmula do Z-Score: (Valor - Média) / Desvio Padrão
        -- O NULLIF evita erro de divisão por zero caso o departamento tenha apenas 1 pedido ou desvio 0
        (VALOR_UNITARIO - Media_Categoria) / NULLIF(Desvio_Padrao_Categoria, 0) AS Z_Score
    FROM CalculoEstatisticas
)
SELECT 
    ID_PEDIDO,
    ID_CLIENTE,
    DEPARTAMENTO,
    VALOR_UNITARIO,
    Media_Categoria,
    Z_Score
FROM CalculoZScore
WHERE Z_Score > 3 -- Filtra apenas anomalias (3 desvios padrão acima da média)
ORDER BY Z_Score DESC;