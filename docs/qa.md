# Controle de Qualidade (QA)

## Visão geral

O QA do projeto opera em duas camadas: verificação de identidades contábeis
nos dados históricos (antes da projeção) e checagem de integridade das projeções
(após reconciliação). A primeira é uma barreira de execução — o pipeline não avança
se ela falhar.

---

## 1. Verificação de consistência contábil (`R/02_consistencia.R`)

O script verifica 5 identidades nos dados históricos (2002–2023) e produz
um objeto `qa_status` no `.GlobalEnv`.

### Identidades verificadas

| # | Checagem | Tolerância | Severidade |
|---|----------|------------|------------|
| 1 | PIB = VAB + Impostos, por geo × ano | `TOL_IDENTIDADE_PIB` = 0,01% | **Fatal** |
| 2 | Soma dos estados = PIB da respectiva região, por ano | `TOL_RECONCILIACAO` = 0,01% | **Fatal** |
| 3 | Soma das regiões = PIB Brasil, por ano | `TOL_RECONCILIACAO` = 0,01% | **Fatal** |
| 4 | Soma das atividades = VAB total, por geo × ano | `TOL_VAB_ATIVIDADES` = 1% | Warning |
| 5 | Impostos: consistência SIDRA vs imputado | `TOL_IMPOSTOS_SIDRA` = 1% | Warning |

As tolerâncias são definidas em `R/config.R`.

### Estrutura do `qa_status`

```r
qa_status <- list(
  ok            = TRUE/FALSE,        # FALSE se qualquer checagem fatal falhar
  checagens     = tibble(...),       # tabela com resultado de cada checagem
  erros_fatais  = tibble(...),       # subset com severidade == "fatal" e status == "falhou"
  warnings      = tibble(...)        # subset com severidade == "warning" e status == "falhou"
)
```

### Comportamento no pipeline

`run_all.R` verifica `qa_status$ok` imediatamente após executar `02_consistencia.R`.
Se for `FALSE`, o pipeline é interrompido com mensagem de erro e o log registra
o evento com nível `"ERROR"`.

```r
if (!isTRUE(qa_status_atual$ok)) {
  salvar_log_execucao(status = "erro_qa")
  stop("QA bloqueante falhou em R/02_consistencia.R. Pipeline interrompido.")
}
```

### Exceção conhecida

A checagem 4 (soma das atividades = VAB total) produz warning para Acre em 2002,
devido a 10 valores `NA` nas Contas Regionais do IBGE para esse ano. Esse desvio
é esperado e está documentado em `diagnostico_dados.md`. O total do IBGE para
Acre 2002 está correto; apenas a decomposição por atividade está incompleta.

---

## 2. Cache com invalidação automática (`R/utils_cache.R`)

O cache da seleção de modelos evita recalcular o CV a cada execução quando
nenhum insumo mudou.

### Como funciona

1. **Criação da metadata** — antes de rodar o CV, `03_projecao.R` chama
   `criar_metadata_cache()` com:
   - Hashes MD5 de objetos R (`todas_series`, `ids`, `ATIVIDADES`, `MACRO_MAP`)
   - Hashes MD5 dos arquivos de entrada (`dados/especiais.rds`, `dados/conta_producao.rds`)
   - Hashes MD5 do script `R/03_projecao.R`
   - Parâmetros relevantes (`H`, `ANO_BASE`, `ANO_FIM`, `MIN_TRAIN`, nomes dos modelos,
     `HORIZONTES_CV`, `PESOS_CV`, `N_FINALISTAS`, `CACHE_SCHEMA_VERSION`)
   - A **assinatura** é o hash MD5 de toda essa estrutura combinada.

2. **Validação** — `cache_valido()` compara a assinatura atual com a salva em
   `dados/selecao_modelos_meta.rds`. O cache é reutilizado **apenas** se as
   assinaturas forem idênticas.

3. **Invalidação automática** — qualquer mudança nos dados, nos parâmetros do CV
   ou no próprio script invalida o cache. Não é necessário deletar arquivos manualmente.

### Schema atual

`CACHE_SCHEMA_VERSION = "bloco4_v1"` — definido em `R/config.R`. Alterar este
valor invalida o cache independentemente de qualquer outra mudança.

---

## 3. Logging estruturado (`R/utils_logging.R`)

Cada execução do pipeline gera um arquivo de log em `output/logs/`.

### Estrutura de um log

```
output/logs/run_all_YYYYMMDD_HHMMSS.json
```

O log registra:
- Timestamp de início
- Branch e commit do git
- Seed global e versão do R
- Eventos de início/fim de cada script com tempo decorrido
- Warnings e erros por série/modelo durante o CV e a projeção final
- Status final: `"sucesso"`, `"erro"` ou `"erro_qa"`

### Quando consultar os logs

- Após uma execução longa: verificar quantos fallbacks ocorreram e em quais séries
- Após uma falha: identificar o script e o erro específico
- Para auditoria: confirmar seed, commit e parâmetros usados em uma determinada rodada

---

## 4. Fallback e limiar de degradação

Durante a projeção final (`R/03_projecao.R`), se o modelo selecionado pelo CV
falhar ao ser ajustado no conjunto completo, o pipeline tenta ARIMA como fallback.

### Registro do fallback

Cada fallback é registrado em `dados/fallback_log.rds` com:
- `serie_id`: identificador da série
- `modelo_original`: modelo que falhou
- `modelo_fallback`: `"arima"` (sempre)
- `etapa`: `"projecao_final"`
- `motivo`: mensagem de erro capturada

### Limiar máximo

`MAX_FALLBACK_PCT = 0.10` (10%) — definido em `R/config.R`.

Se a fração de séries com fallback exceder esse limite, o pipeline para com erro:

```
Degradação excessiva: X.X% de fallbacks (limite = 10%)
```

Isso protege contra situações em que um pacote quebra silenciosamente e
degrada a maioria das projeções para ARIMA sem avisar.

### Diagnóstico dos fallbacks

O CSV `painel/data/diagnostico.csv` inclui uma coluna `fallback` (TRUE/FALSE)
que permite identificar visualmente no painel quais séries sofreram fallback
para cada território.

---

## 5. Verificação de integridade pós-reconciliação

`R/04_reconciliacao.R` verifica ao final:

- Desvio máximo em PIB = VAB + Impostos: deve ser 0% após reconciliação
- Desvio máximo em soma dos estados = região: deve ser < 0,00001%
- Desvio máximo em soma das regiões = Brasil: deve ser < 0,00001%
- Desvio máximo em soma das atividades = VAB total: deve ser < 0,00000001%

Se qualquer verificação falhar, o script emite mensagem de aviso mas não
interrompe o pipeline (os desvios esperados são puramente numéricos, de ponto flutuante).
