# Painel de Projeção do PIB dos Estados Brasileiros (2024–2031)

Projeções do PIB nominal, VAB por macrossetor e atividade, impostos, deflator e crescimento real para **27 UFs + 5 regiões + Brasil**, com restrições de agregação contábil (benchmarking top-down).

> Desenvolvido pela **CGEES/SEPLAN-RR** com dados das Contas Regionais do IBGE (2002–2023).  
> **Autor:** Yuri Cesar de Lima e Silva — Analista de Planejamento e Orçamento | Chefe da Divisão de Estudos e Análises Sociais

---

## Painel Interativo

**[https://yuricesarsilva.github.io/painel_projecao_pib_estados](https://yuricesarsilva.github.io/painel_projecao_pib_estados)**

**[Nota Metodológica](https://yuricesarsilva.github.io/painel_projecao_pib_estados/metodologia.html)**

O painel permite visualizar:
- Séries históricas (2002–2023) e projeções (2024–2031) com intervalo de confiança de 95%
- Destaque analítico para `2024–2027` como **horizonte operacional**
- Tratamento de `2028–2031` como **horizonte exploratório**, com maior cautela interpretativa
- PIB nominal, VAB total, impostos, PIB real acumulado e deflator implícito acumulado (índices base 100 = 2002)
- VAB desagregado por macrossetor (agropecuária, indústria, serviços, administração pública)
- VAB desagregado por atividade econômica (12 atividades)
- Comparativo entre territórios
- Tabela interativa com todas as variáveis e fontes de dados (série principal, macrossetor, atividade)
- Filtro de anos de projeção exibidos (padrão: 3 anos, máximo: 8 anos)
- Números formatados no padrão brasileiro (vírgula decimal, ponto milhar)
- Alternância modo claro/escuro via botão na barra superior

---

## Estrutura do Projeto

```
.
├── R/
│   ├── 01_leitura_dados.R       # Leitura e organização dos dados brutos
│   ├── 02_consistencia.R        # Verificação de identidades contábeis
│   ├── 03_projecao.R            # Modelagem e projeção (~1.089 séries, 10 modelos)
│   ├── 04_reconciliacao.R       # Benchmarking top-down (BR → região → UF)
│   ├── 05_output.R              # Geração de tabelas Excel e gráficos
│   ├── 06_exportar_painel.R     # Exporta CSVs para o painel interativo
│   └── run_all.R                # Executa o pipeline completo em sequência
├── painel/
│   ├── painel.qmd               # Painel Quarto Dashboard + shinylive
│   ├── metodologia.html         # Nota metodológica (publicada no GitHub Pages)
│   ├── custom.css               # Estilos customizados (navbar, sidebar, tabelas)
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
- **Período histórico:** 2002–2023 (22 observações anuais)
- **Horizonte operacional recomendado:** 2024–2027
- **Horizonte exploratório:** 2028–2031
- **Cobertura:** 27 UFs, 5 regiões geográficas e Brasil (33 territórios)
- **Variáveis modeladas:** índices de volume e preço por atividade/macrossetor, log dos impostos

### Modelos de Projeção

Para cada série temporal (~1.089 no total), o script `03_projecao.R` seleciona automaticamente o melhor entre **10 modelos** via validação cruzada com janela expansiva (*expanding window CV*, mínimo de 15 observações de treino):

| Sigla | Modelo | Descrição |
|-------|--------|-----------|
| `RW` | Passeio aleatório com drift | Tendência linear simples como linha de base |
| `ARMA` | Média móvel autorregressiva | Dependência linear de curto prazo |
| `ARIMA` | ARIMA automático | Diferenciação + seleção por AIC |
| `SARIMA` | ARIMA sazonal (período 2) | Captura ciclos bienais |
| `ETS` | Suavização exponencial | Nível, tendência e sazonalidade adaptativa |
| `ETS-A` | ETS com tendência amortecida | Crescimento desacelerando no horizonte |
| `THETA` | Método Theta | Combinação de regressão linear e suavização |
| `NNAR` | Rede neural autorregressiva | Captura não-linearidades |
| `PROPHET` | Prophet (Meta) | Tendência, sazonalidade e calendário |
| `SSM` | Modelo de espaço de estados | Filtro de Kalman (local linear trend) |

A seleção usa o menor **MASE** (*Mean Absolute Scaled Error*) no período de validação (2017–2023).

### Interpretação do Horizonte

- `2024–2027`: horizonte principal para leitura operacional e comparação pública.
- `2028–2031`: horizonte exploratório, mantido para referência técnica, mas com maior fragilidade interpretativa.
- O painel sinaliza visualmente o trecho exploratório para reduzir leitura excessivamente precisa dos anos mais distantes.

### Séries Projetadas

| Grupo | Variáveis | Nº de séries |
|-------|-----------|-------------|
| A — Macrossetor × geo | idx_volume e idx_preco (4 macrosetores × 33 geos) | ~264 |
| B — Impostos × geo | log(impostos_nominal) | 33 |
| C — Atividade × geo | idx_volume e idx_preco (12 atividades × 33 geos) | ~792 |

### Reconciliação (Benchmarking Top-Down)

O script `04_reconciliacao.R` garante consistência hierárquica por fator multiplicativo proporcional:

1. **Brasil** como âncora (valor projetado inalterado)
2. **Regiões** ajustadas para somar ao Brasil
3. **UFs** ajustadas para somar à respectiva região
4. **Identidade contábil** PIB = VAB + Impostos preservada em todos os níveis
5. **Macrossetores e atividades** escalonados para bater com o VAB total reconciliado

### Índices Acumulados

As séries de volume e deflator são apresentadas como índices com **base 100 = 2002**:

- `idx_vol_pib` = (vol_enc_t / vol_enc_2002) × 100
- `idx_deflator` = (PIB_nominal_t / PIB_nominal_2002) / (idx_vol_t / 100) × 100

---

## Como Executar

### Pré-requisitos

- R ≥ 4.2
- Pacotes: `tidyverse`, `forecast`, `prophet`, `readxl`, `openxlsx`
- Dados brutos do IBGE em `base_bruta/` (não incluídos no repositório)

### Pipeline completo

```r
source("R/run_all.R")
```

### Preview local do painel

Para visualizar o painel localmente com os CSVs mais recentes de `painel/data/`, use:

```bash
quarto preview painel/painel.qmd
```

Ou, no Windows, use o atalho do projeto:

```powershell
.\preview_painel.ps1
```

Ou, se preferir via R:

```bash
Rscript preview_painel.R
```

Se o preview via `shinylive` apresentar incompatibilidades no navegador local, use o modo de preview em R nativo:

```bash
Rscript preview_painel_local.R
```

Se quiser apenas gerar o HTML localmente, sem abrir servidor de preview:

```bash
quarto render painel/painel.qmd
```

Ou:

```powershell
.\render_painel.ps1
```

No modo local, o painel passa a ler os arquivos versionados em `painel/data/`, sem depender do GitHub Pages.

Se o preview for aberto a partir de `painel/`, o arquivo `painel/.Rprofile` garante que o Quarto use o mesmo ambiente `renv` do projeto.

### Etapas individuais

```r
source("R/01_leitura_dados.R")   # ~2 min
source("R/02_consistencia.R")    # ~1 min
source("R/03_projecao.R")        # ~30–60 min (1ª vez; usa cache nas seguintes)
source("R/04_reconciliacao.R")   # ~2 min
source("R/05_output.R")          # ~5 min
source("R/06_exportar_painel.R") # ~1 min
```

> **Cache:** `03_projecao.R` salva os modelos em `dados/selecao_modelos.rds`. Delete esse arquivo ao adicionar novas séries para forçar o reprocessamento.

### Atualizar o painel

Após rodar o pipeline, os CSVs em `painel/data/` são atualizados. Faça commit e push — o GitHub Actions republica automaticamente:

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
| `output/graficos/` | Gráficos PNG por variável e por território |
| `painel/data/serie_principal.csv` | Séries históricas + projetadas, 5 variáveis, IC 95% |
| `painel/data/vab_macrossetor.csv` | VAB histórico + projetado por macrossetor, IC 95% |
| `painel/data/vab_atividade.csv` | VAB histórico + projetado por atividade, IC 95% |
| `painel/metodologia.html` | Nota metodológica publicada no GitHub Pages |

---

## Publicação do Painel

O painel é publicado automaticamente no GitHub Pages via GitHub Actions a cada push que altere arquivos em `painel/`. O workflow está em [`.github/workflows/publish-painel.yml`](.github/workflows/publish-painel.yml).

Tecnologias:
- [Quarto Dashboard](https://quarto.org/docs/dashboards/) — estrutura do painel
- [shinylive](https://shiny.posit.co/py/docs/shinylive.html) — R/Shiny via WebAssembly (sem servidor)
- [GitHub Pages](https://pages.github.com/) — hospedagem estática

---

## Licença

Uso interno — SEPLAN/RR. Dados do IBGE sujeitos à [política de uso do IBGE](https://www.ibge.gov.br/acesso-informacao/institucional/politica-de-dados-abertos.html).
