# Projeções dos PIBs Estaduais Brasileiros (2024–2031)

Projeções do PIB nominal, VAB por macrossetor e atividade, impostos, deflatores e crescimento real para **27 UFs + 5 regiões + Brasil**, com restrições de agregação contábil (benchmarking top-down).

> Desenvolvido pela **SEPLAN/RR** com dados das Contas Regionais do IBGE (2002–2023).

---

## Painel Interativo

Acesse o painel com os resultados em:

**[https://yuricesarsilva.github.io/relatorio_projecao_pib_estados](https://yuricesarsilva.github.io/relatorio_projecao_pib_estados)**

O painel permite visualizar:
- Séries históricas (2002–2023) e projeções (2024–2031) com intervalo de confiança de 95%
- PIB nominal, VAB total, impostos, crescimento real e deflator
- VAB desagregado por macrossetor (agropecuária, indústria, serviços, administração pública)
- VAB desagregado por atividade econômica (12 atividades)
- Comparativo entre territórios
- Filtros por território (UF, região, Brasil) e variável
- Modo claro/escuro

---

## Estrutura do Projeto

```
.
├── R/
│   ├── 01_leitura_dados.R       # Leitura e organização dos dados brutos
│   ├── 02_consistencia.R        # Verificação de identidades contábeis
│   ├── 03_projecao.R            # Modelagem e projeção (~1.089 séries)
│   ├── 04_reconciliacao.R       # Benchmarking top-down (BR → região → UF)
│   ├── 05_output.R              # Geração de tabelas Excel e gráficos
│   ├── 06_exportar_painel.R     # Exporta CSVs para o painel interativo
│   └── run_all.R                # Executa o pipeline completo em sequência
├── painel/
│   ├── painel.qmd               # Painel Quarto Dashboard + shinylive
│   ├── data/                    # CSVs exportados (versionados no git)
│   └── _extensions/             # Extensão quarto-ext/shinylive
├── base_bruta/                  # Dados brutos do IBGE (não versionados)
├── dados/                       # Dados processados intermediários (não versionados)
└── output/                      # Tabelas e gráficos gerados (não versionados)
```

---

## Metodologia

### Dados

- **Fonte:** IBGE — Contas Regionais do Brasil
- **Período histórico:** 2002–2023
- **Cobertura:** 27 UFs, 5 regiões geográficas e Brasil
- **Variáveis:** PIB nominal, VAB por macrossetor e atividade, impostos sobre produtos, volume encadeado

### Modelos de Projeção

Para cada série temporal (~1.089 no total), o script `03_projecao.R` seleciona automaticamente o melhor entre 9 modelos via validação cruzada com janela expansiva (*expanding window CV*):

| Modelo | Descrição |
|--------|-----------|
| `naive` | Último valor observado (benchmark) |
| `rw_drift` | Random walk com drift |
| `ets` | Suavização exponencial (ETS) |
| `arima` | ARIMA automático |
| `tslm_trend` | Regressão linear com tendência |
| `tslm_log` | Regressão log-linear com tendência |
| `tslm_trend_season` | Tendência + sazonalidade |
| `var_br` | VAR bivariado com série nacional |
| `lm_br` | Regressão na série nacional |

A seleção usa o menor **MASE** (Mean Absolute Scaled Error) na validação.

### Séries Projetadas

As projeções cobrem três grupos:

1. **Macrossetor × geo** — índices de volume e preço para 4 macrosetores × 33 territórios (≈264 séries)
2. **Impostos** — log dos impostos nominais para 33 territórios
3. **Atividade × geo** — índices de volume e preço para 12 atividades × 33 territórios (≈792 séries)

### Reconciliação (Benchmarking Top-Down)

O script `04_reconciliacao.R` impõe consistência hierárquica:

- **Nível 1:** Brasil (restrição externa — projeções ajustadas por fator multiplicativo)
- **Nível 2:** Regiões devem somar ao Brasil
- **Nível 3:** UFs devem somar à respectiva região

O mesmo procedimento é aplicado ao VAB por macrossetor e por atividade.

---

## Como Executar

### Pré-requisitos

- R ≥ 4.2
- Pacotes: `tidyverse`, `forecast`, `fpp3`, `readxl`, `openxlsx`, `tseries`
- Dados brutos do IBGE em `base_bruta/` (não incluídos no repositório)

### Executar o pipeline completo

```r
# No console R, a partir da raiz do projeto:
source("R/run_all.R")
```

### Executar etapas individualmente

```r
source("R/01_leitura_dados.R")   # ~2 min
source("R/02_consistencia.R")    # ~1 min
source("R/03_projecao.R")        # ~30–60 min (1ª vez; usa cache nas seguintes)
source("R/04_reconciliacao.R")   # ~2 min
source("R/05_output.R")          # ~5 min
source("R/06_exportar_painel.R") # ~1 min
```

> **Nota sobre cache:** O script `03_projecao.R` salva os modelos selecionados em `dados/selecao_modelos.rds`. Nas execuções seguintes, o CV é pulado e os modelos são reutilizados. Ao adicionar novas séries, delete esse arquivo para forçar o reprocessamento.

### Atualizar o painel após nova execução

Após rodar o pipeline, os CSVs em `painel/data/` são atualizados. Basta fazer commit e push — o GitHub Actions republica automaticamente:

```bash
git add painel/data/
git commit -m "Atualiza dados do painel"
git push origin main
```

---

## Outputs Gerados

| Arquivo/Pasta | Conteúdo |
|---------------|----------|
| `output/tabelas/projecoes_pib_estadual.xlsx` | Tabelas com projeções (9 abas) |
| `output/graficos/todas_geos/` | 21 plots facetados por variável |
| `output/graficos/por_geo/` | 33 plots individuais por território |
| `output/graficos/por_geo_atividade/` | 33 gráficos de área empilhada por atividade |
| `painel/data/serie_principal.csv` | Séries históricas + projetadas, 5 variáveis, IC 95% |
| `painel/data/vab_macrossetor.csv` | VAB histórico + projetado por macrossetor, IC 95% |
| `painel/data/vab_atividade.csv` | VAB histórico + projetado por atividade, IC 95% |

---

## Publicação do Painel

O painel é publicado automaticamente no GitHub Pages via GitHub Actions a cada push que altere arquivos em `painel/`. O workflow está em [`.github/workflows/publish-painel.yml`](.github/workflows/publish-painel.yml).

Tecnologias utilizadas:
- [Quarto Dashboard](https://quarto.org/docs/dashboards/) — estrutura do painel
- [shinylive](https://shiny.posit.co/py/docs/shinylive.html) — R/Shiny rodando no browser via WebAssembly (sem servidor)
- [GitHub Pages](https://pages.github.com/) — hospedagem estática gratuita

---

## Licença

Uso interno — SEPLAN/RR. Dados do IBGE sujeitos à [política de uso do IBGE](https://www.ibge.gov.br/acesso-informacao/institucional/politica-de-dados-abertos.html).