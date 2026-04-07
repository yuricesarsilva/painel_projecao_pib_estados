# Arquitetura do Projeto

## Visão geral

O projeto projeta PIB nominal, VAB, impostos, deflatores e crescimento real para
27 UFs + 5 regiões + Brasil (horizonte 2024–2031), com restrições de agregação
contábil impostas por benchmarking top-down.

---

## Fluxo de dados

```
[FTP IBGE / SIDRA tabela 5938]
        │
        ▼ 00_download_ibge.R  (opcional — ativa com DOWNLOAD_ANTES_DE_RODAR)
base_bruta/
  Conta_da_Producao_{ANO_INI}_{ANO_FIM}_xls/  ← 33 arquivos Excel (IBGE)
  Especiais_{ANO_INI}_{ANO_FIM}_xls/          ← tab01–tab07 (IBGE)
  PIB e Impostos (SIDRA).xlsx                 ← PIB + impostos + VAB por UF
painel/data/
  status_dados.json    ← status do último download (ok / erro + código)
        │
        ▼ 01_leitura_dados.R
dados/
  especiais.rds          ← PIB, VAB, impostos, índices (tidy)
  conta_producao.rds     ← VBP/CI/VAB por atividade × geo × ano
        │
        ▼ 02_consistencia.R (barreira QA)
dados/
  consistencia.rds       ← resultado das 5 checagens contábeis
        │
        ▼ 03_projecao.R (~20–40 min, cache automático)
dados/
  selecao_modelos.rds         ← modelo vencedor por série (cache CV)
  selecao_modelos_meta.rds    ← metadata de invalidação do cache
  metricas_cv_detalhadas.rds  ← métricas por série × modelo × horizonte
  projecoes_brutas.rds        ← projeções + IC 95% por série × ano
  params_modelos.rds          ← modelo, parâmetros, MASE por série
  fallback_log.rds            ← séries que precisaram de fallback ARIMA
  vab_macro_hist.rds          ← histórico VAB macro (para gráficos)
  vab_atividade_hist.rds      ← histórico VAB atividade (para gráficos)
  vab_macrossetor_proj.rds    ← VAB macro projetado + IC
  vab_atividade_proj.rds      ← VAB atividade projetado + IC
  projecoes_derivadas.rds     ← PIB, VAB total, impostos, deflator
        │
        ▼ 04_reconciliacao.R
dados/
  projecoes_reconciliadas.rds     ← PIB reconciliado por geo × ano
  vab_macro_reconciliado.rds      ← VAB macro reconciliado
  vab_atividade_reconciliada.rds  ← VAB atividade reconciliada
        │
        ├─▼ 05_output.R
        │  output/tabelas/projecoes_pib_estadual.xlsx  (9 abas)
        │  output/graficos/                            (~56 PNGs)
        │  output/logs/                                (logs de execução)
        │
        └─▼ 06_exportar_painel.R
           painel/data/serie_principal.csv   ← histórico + proj 2024–2026
           painel/data/vab_macrossetor.csv   ← VAB macro histórico + proj
           painel/data/vab_atividade.csv     ← VAB atividade histórico + proj
           painel/data/diagnostico.csv       ← modelos, métricas, fallback (aba Diagnóstico)
           painel/data/tabela_painel.xlsx    ← tabela completa para download (3 abas, colunas em PT)
```

---

## Scripts e utilitários

| Script/Arquivo | Papel | Entradas | Saídas | Tempo estimado |
|----------------|-------|----------|--------|----------------|
| `R/config.R` | Parâmetros centrais | — | variáveis no `.GlobalEnv` | < 1 s |
| `R/utils_cache.R` | Cache com invalidação por hash MD5 | — | funções `criar_metadata_cache`, `cache_valido`, `salvar_cache_com_metadata` | < 1 s |
| `R/utils_logging.R` | Logging estruturado por execução | — | funções `inicializar_log_execucao`, `registrar_evento_log`, `salvar_log_execucao` | < 1 s |
| `R/run_all.R` | Orquestra o pipeline completo | config.R, utils | — | depende dos scripts |
| `R/00_download_ibge.R` | Download automático do FTP IBGE e SIDRA (opcional) | config.R | base_bruta/, painel/data/status_dados.json | ~2–5 min |
| `R/01_leitura_dados.R` | Lê todos os dados brutos | base_bruta/ | dados/*.rds | ~2 min |
| `R/02_consistencia.R` | Verifica 5 identidades contábeis | dados/especiais.rds | dados/consistencia.rds, `qa_status` no `.GlobalEnv` | ~1 min |
| `R/03_projecao.R` | CV two-stage + 7 modelos + projeção | dados/especiais.rds, dados/conta_producao.rds | dados/selecao_modelos.rds, dados/projecoes_brutas.rds, ... | ~20–40 min (1ª vez) |
| `R/04_reconciliacao.R` | Benchmarking top-down BR → reg → UF | dados/projecoes_derivadas.rds, ... | dados/projecoes_reconciliadas.rds, ... | ~2 min |
| `R/05_output.R` | Gera Excel e gráficos | dados/*_reconciliado.rds | output/tabelas/, output/graficos/ | ~5 min |
| `R/06_exportar_painel.R` | Exporta CSVs para o painel | dados/*_reconciliada.rds | painel/data/*.csv | ~1 min |

---

## Configuração central (`R/config.R`)

Todos os parâmetros críticos ficam em `PROJETO_CONFIG` e são exportados para
o `.GlobalEnv` via `list2env()`. Alterar qualquer parâmetro aqui afeta
automaticamente todos os scripts que dependem dele.

| Parâmetro | Valor atual | Descrição |
|-----------|-------------|-----------|
| `ANO_HIST_INI` | 2002 | Início da série histórica |
| `ANO_HIST_FIM` | 2023 | Fim da série histórica |
| `H` | 8 | Horizonte técnico de projeção (anos) |
| `ANO_PROJ_FIM` | 2031 | Último ano projetado nas saídas técnicas |
| `H_PAINEL` | 3 | Horizonte público do painel |
| `ANO_PAINEL_PROJ_FIM` | 2026 | Último ano exibido no painel público |
| `MIN_TRAIN` | 15 | Mínimo de observações de treino no CV |
| `HORIZONTES_CV` | c(1,2,3) | Horizontes avaliados no CV |
| `PESOS_CV` | c(0.5,0.3,0.2) | Pesos por horizonte no MASE ponderado |
| `N_FINALISTAS` | 3 | Top K do stage 1 que avançam ao stage 2 |
| `MAX_FALLBACK_PCT` | 0.10 | Limite máximo de séries com fallback (10%) |
| `SEED_GLOBAL` | 12345 | Semente global para reprodutibilidade |
| `CACHE_SCHEMA_VERSION` | "bloco4_v1" | Identificador do schema de cache |
| `IBGE_FTP_BASE` | `https://ftp.ibge.gov.br/Contas_Regionais` | URL raiz do FTP IBGE |
| `SIDRA_TABELA_ID` | 5938 | Tabela SIDRA (PIB + impostos + VAB por UF) |
| `DOWNLOAD_DIR` | `"base_bruta"` | Pasta de destino do download |
| `STATUS_JSON_PATH` | `"painel/data/status_dados.json"` | Arquivo de status do download |
| `TOL_VALIDACAO_DOWNLOAD` | 0.001 | Desvio máximo aceito na validação cruzada (0,1%) |

---

## Convenções de nomenclatura

**`serie_id`** — identificador único de cada série temporal:
- Macrossetor: `"<geo>|<macrossetor>|<variavel>"` (ex: `"Roraima|agropecuaria|idx_volume"`)
- Atividade: `"<geo>|ativ__<atividade>|<variavel>"` (ex: `"Roraima|ativ__construcao|idx_preco"`)
- Impostos: `"<geo>|total|log_impostos"` (ex: `"Brasil|total|log_impostos"`)

O prefixo `ativ__` evita colisão entre séries de atividade e macrossetor quando
ambos têm a mesma atividade (ex: agropecuária existe como macrossetor e como atividade).

**`geo_tipo`** — tipo de território: `"estado"`, `"regiao"`, `"pais"`.

**`variavel`** — variável modelada: `"idx_volume"`, `"idx_preco"`, `"log_impostos"`.

---

## O que está e não está versionado no git

| Diretório/Arquivo | Versionado? | Motivo |
|-------------------|-------------|--------|
| `R/` | Sim | Scripts analíticos |
| `painel/` | Sim | Painel e dados públicos |
| `docs/` | Sim | Documentação técnica |
| `*.md` | Sim | Documentação e planejamento |
| `renv.lock` | Sim | Reprodutibilidade do ambiente |
| `base_bruta/` | Não | Dados IBGE, tamanho e licença |
| `dados/` | Não | Dados intermediários, reproduced do pipeline |
| `output/` | Não | Outputs, reproduced do pipeline |

---

## Fluxo de publicação do painel

```
1. (Opcional) Baixar dados atualizados do IBGE:
      source("R/00_download_ibge.R")
   Ou integrado ao pipeline:
      DOWNLOAD_ANTES_DE_RODAR <- TRUE
      source("R/run_all.R")

2. Executar pipeline local (sem download):
      source("R/run_all.R")

4. Versionar os CSVs gerados:
      git add painel/data/*.csv
      git commit -m "Atualiza: rebuild analítico YYYY-MM-DD"

5. Push para main:
      git push origin main

4. GitHub Actions (publish-painel.yml) dispara automaticamente:
      → Instala R 4.4.0 + renv + Quarto
      → quarto render painel/painel.qmd
      → Publica em gh-pages

5. Painel disponível em:
      https://yuricesarsilva.github.io/painel_projecao_pib_estados/
```

Para preview local antes do push:
```r
Rscript preview_painel_local.R
```
