# Modelagem e Projeção

## Visão geral

O script `R/03_projecao.R` modela ~1.089 séries temporais anuais e projeta
2024–2031. A seleção de modelos usa validação cruzada two-stage com janela
expansiva e avaliação em múltiplos horizontes. As projeções individuais são
depois reconciliadas por `R/04_reconciliacao.R` para impor restrições contábeis
de agregação.

---

## 1. Séries modeladas

As séries são organizadas em três grupos:

| Grupo | Descrição | Contagem | Variáveis |
|-------|-----------|----------|-----------|
| A — Macrossetor × geo | Índices encadeados de 4 macrossetores × 33 geos | 264 séries | `idx_volume`, `idx_preco` |
| B — Impostos × geo | Log dos impostos nominais de 33 geos | 33 séries | `log_impostos` |
| C — Atividade × geo | Índices encadeados de 12 atividades × 33 geos | ~792 séries | `idx_volume`, `idx_preco` |

**Período histórico:** 2003–2023 para grupos A e C (os índices encadeados
exigem o lag do ano anterior, perdendo 2002); 2002–2023 para o grupo B
(impostos em log não dependem de lag). O número efetivo de observações de
treino é portanto 21 (grupos A/C) ou 22 (grupo B).

**Macrossetores (grupo A):** agropecuaria, industria, adm_publica, servicos.
O macrossetor `industria` é a soma de 4 atividades (ind_extrativa,
ind_transformacao, eletricidade_gas_agua, construcao); `servicos` é a soma
de 6 atividades. Os índices de macrossetor são DERIVADOS — calculados pela
agregação dos `val_corrente`/`val_preco_ant` das atividades individuais, não
lidos diretamente do IBGE.

**Atividades (grupo C):** 12 atividades individuais — agropecuaria,
ind_extrativa, ind_transformacao, eletricidade_gas_agua, construcao,
comercio_veiculos, transporte_armazenagem, informacao_comunicacao,
financeiro_seguros, imobiliaria, adm_publica, outros_servicos. O `serie_id`
usa o prefixo `ativ__` para evitar colisão com macrossetores de mesmo nome
(ex: `"Roraima|ativ__agropecuaria|idx_volume"`).

---

## 2. Família de modelos

Sete modelos candidatos são avaliados para cada série:

| ID | Modelo | Descrição |
|----|--------|-----------|
| `rw` | Random Walk | Passeio aleatório com drift; benchmark ingênuo |
| `arma` | ARMA | auto.arima com d=0 forçado (série estacionária) |
| `arima` | ARIMA | auto.arima livre para d=0,1,2 |
| `ets` | ETS | Suavização exponencial padrão |
| `ets_amort` | ETS amortecido | ETS com tendência amortecida (damped=TRUE) |
| `theta` | Theta | Decomposição Theta (thetam via forecast) |
| `ssm` | Espaço de estados | structural time series via StructTS |

### Modelos excluídos do baseline

| Modelo | Motivo da exclusão |
|--------|-------------------|
| SARIMA | `period=2` sem respaldo em dados anuais; componente sazonal espúrio |
| NNAR | Instável com ~22 observações; tendência a sobreajuste |
| Prophet | Superdimensionado para séries anuais curtas; requer colunas especiais e dependência externa |

---

## 3. Validação cruzada two-stage

### Por que dois estágios

O CV expanding-window com h=1/2/3 exige múltiplos ajustes por série. Com 7
modelos e ~1.089 séries, um único estágio com avaliação precisa seria
computacionalmente inviável (~20 min apenas para ARIMA sem aproximação).
O two-stage resolve isso:

- **Stage 1 (triagem rápida):** todos os 7 modelos com `approximation=TRUE`,
  `stepwise=TRUE` para ARIMA/ARMA. Identifica os top `N_FINALISTAS` por
  MASE ponderado.
- **Stage 2 (avaliação precisa):** apenas os `N_FINALISTAS=3` finalistas,
  com `approximation=FALSE`, `stepwise=FALSE`, e limites de ordem. Modelos
  não-ARIMA (rw, ets, ets_amort, theta, ssm) reutilizam os resultados do
  stage 1 — a aproximação não os afeta. Só ARIMA e ARMA são reavaliados.

O vencedor é o modelo com menor MASE ponderado no stage 2.

### Janela expansiva

Para cada série de comprimento `n`, as janelas de CV são:

```
Treino: [1 .. MIN_TRAIN+k-1]   para k = 1, 2, ..., n - MIN_TRAIN - h_max + 1
Teste:  [MIN_TRAIN+k .. MIN_TRAIN+k+h_max-1]
```

Com `n=21`, `MIN_TRAIN=15`, `h_max=3`: 4 janelas de CV.
Com `n=22` (impostos): 5 janelas de CV.

### MASE ponderado

O MASE (Mean Absolute Scaled Error) por horizonte é:

```
MASE_h = mean(|erro_h|) / escala_naive
```

onde `escala_naive` é o MAE do random walk de 1 passo no conjunto de treino.

O MASE ponderado agrega os três horizontes com pesos `PESOS_CV`:

```
MASE_pond = 0.5 × MASE_h1 + 0.3 × MASE_h2 + 0.2 × MASE_h3
```

O peso maior em h=1 reflete a prioridade operacional do painel (2024–2026).

### Parâmetros do CV em `R/config.R`

| Parâmetro | Valor | Descrição |
|-----------|-------|-----------|
| `MIN_TRAIN` | 15 | Mínimo de observações no treino |
| `HORIZONTES_CV` | c(1, 2, 3) | Horizontes avaliados |
| `PESOS_CV` | c(0.5, 0.3, 0.2) | Pesos por horizonte no MASE ponderado |
| `N_FINALISTAS` | 3 | Modelos que avançam do stage 1 ao stage 2 |

### Especificação ARIMA no stage 2 e na projeção final

Para limitar o espaço de busca a séries curtas (~22 obs):

```r
max.p = 3, max.q = 3, max.d = 2, max.P = 0, max.Q = 0, max.D = 0
stepwise = FALSE, approximation = FALSE
```

`max.P/Q/D = 0` desativa a componente sazonal (dados anuais). A desativação
de `stepwise` e `approximation` garante busca exaustiva dentro dos limites
definidos.

---

## 4. Derivações contábeis

### VAB nominal (macrossetor)

Dado o VAB nominal observado em 2023 (`vab_2023`) e os índices projetados:

```
VAB_nominal(t) = vab_2023 × ∏[s=2024..t] (idx_volume(s) × idx_preco(s))
```

O produto cumulativo começa em 2024. O VAB total por geo × ano é a soma
dos 4 macrossetores.

### VAB nominal (atividade individual)

Mesma estrutura, usando `vab_2023_ativ` de `conta_producao.rds`:

```
VAB_ativ(t) = vab_2023_ativ × ∏[s=2024..t] (idx_volume_ativ(s) × idx_preco_ativ(s))
```

Os IC 95% são propagados da mesma forma usando `idx_lo95` e `idx_hi95`.

### PIB nominal

```
PIB_nominal(t) = VAB_total(t) + impostos(t)
```

onde `impostos(t) = exp(log_impostos_projetado(t))`.

### Deflator

```
deflator(t) = PIB_nominal(t) / (PIB_2023 × ∏[s=2024..t] idx_volume_pib(s))
```

onde `idx_volume_pib` é a média ponderada dos `idx_volume` dos macrossetores,
com pesos proporcionais ao VAB de 2023.

Pós-reconciliação, o deflator é recalculado com o PIB nominal reconciliado,
mantendo o `tx_cresc_pib_real` inalterado (índices encadeados não são
aditivos espacialmente).

---

## 5. Reconciliação top-down

O benchmarking proporcional impõe as restrições de agregação em dois passos:

### Passo 1 — Brasil → Regiões

```
fator_reg(t) = PIB_Brasil(t) / Σ PIB_regiao_bruto(t)
PIB_regiao_rec(t) = PIB_regiao_bruto(t) × fator_reg(t)
```

O PIB do Brasil é a âncora; o fator é único por ano.

### Passo 2 — Região → Estados

```
fator_uf(t) = PIB_regiao_rec(t) / Σ PIB_uf_bruto(t)    [dentro da região]
PIB_uf_rec(t) = PIB_uf_bruto(t) × fator_uf(t)
```

O mesmo fator é aplicado ao VAB total e aos impostos de cada geo, preservando
a identidade `PIB = VAB + impostos` em todos os níveis. Macrossetores e
atividades individuais são escalonados pelo mesmo fator do VAB total para
manter a consistência interna.

---

## 6. Horizontes operacional e técnico

| Horizonte | Parâmetro | Valor | Uso |
|-----------|-----------|-------|-----|
| Técnico | `H` | 8 | Todas as saídas em `dados/` e `output/` |
| Operacional / painel | `H_PAINEL` | 3 | CSVs em `painel/data/` |
| Ano fim técnico | `ANO_PROJ_FIM` | 2031 | Saídas técnicas |
| Ano fim painel | `ANO_PAINEL_PROJ_FIM` | 2026 | Painel público |

O horizonte técnico (h=8) fornece margem para análises de sensibilidade e
cenários alternativos. O horizonte operacional (h=3, 2024–2026) é o que
alimenta o painel público e corresponde ao foco do CV (HORIZONTES_CV = c(1,2,3)).

---

## 7. Como interpretar o CSV de diagnóstico

O arquivo `painel/data/diagnostico.csv` (gerado por `R/06_exportar_painel.R`)
contém uma linha por série modelada, com as seguintes colunas:

| Coluna | Descrição |
|--------|-----------|
| `geo` | Território (UF, região ou Brasil) |
| `geo_tipo` | `"estado"`, `"regiao"` ou `"pais"` |
| `serie_tipo` | `"Macrossetor"`, `"Atividade"` ou `"Impostos"` |
| `macrossetor` | Macrossetor (NA para atividades e impostos) |
| `atividade` | Atividade individual (NA para macrossetor/impostos) |
| `variavel` | `idx_volume`, `idx_preco` ou `log_impostos` |
| `modelo` | Modelo vencedor selecionado pelo CV |
| `parametros` | Especificação do modelo (ex: `ARIMA(1,1,0)`) |
| `mase_ponderado` | MASE ponderado do vencedor (métrica de seleção) |
| `mase_h1` | MASE em horizonte h=1 |
| `mase_h2` | MASE em horizonte h=2 |
| `mase_h3` | MASE em horizonte h=3 |
| `fallback` | TRUE se o modelo vencedor falhou e usou ARIMA como substituto |

**Pontos de atenção ao analisar:**
- `mase_ponderado > 1` indica que o melhor modelo disponível performa pior
  que o random walk de 1 passo — sinal de série difícil de prever.
- `fallback = TRUE` não indica necessariamente má qualidade — o ARIMA de
  fallback pode ter performance similar ao modelo original. Verificar `modelo`
  e `mase_ponderado` para avaliar.
- A aba "Diagnóstico" no painel filtra automaticamente pelo território
  selecionado na sidebar.
