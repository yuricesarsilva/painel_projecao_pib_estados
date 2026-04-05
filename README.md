# Painel de Projeção do PIB dos Estados Brasileiros (2024–2031)

Projeções do PIB nominal, VAB por macrossetor e atividade, impostos, deflator e crescimento real para **27 UFs + 5 regiões + Brasil**, com restrições de agregação contábil (benchmarking top-down).

> Desenvolvido pela **CGEES/SEPLAN-RR** com dados das Contas Regionais do IBGE (2002–2023).  
> **Autor:** Yuri Cesar de Lima e Silva — Analista de Planejamento e Orçamento | Chefe da Divisão de Estudos e Análises Sociais

---

## Painel Interativo

**[https://yuricesarsilva.github.io/painel_projecao_pib_estados](https://yuricesarsilva.github.io/painel_projecao_pib_estados)**

**[Nota Metodológica](https://yuricesarsilva.github.io/painel_projecao_pib_estados/metodologia.html)**

## Atualização do Horizonte Público

Esta versão do projeto adota uma separação explícita entre:

- **painel público (`h=3`)**: o produto visual e os CSVs consumidos pelo painel passam a exibir apenas `2024–2026`;
- **saída técnica (`h=8`)**: o horizonte completo `2024–2031` continua sendo gerado e fica disponível em `output/tabelas/projecoes_painel_h8.xlsx`.
- **cópia técnica (`h=3`)**: uma cópia estrutural idêntica da planilha técnica também é gerada em `output/tabelas/projecoes_painel_h3.xlsx`, mas restrita ao horizonte público `2024–2026`.

Sempre que houver referência antiga a `2024–2031` como horizonte do painel, considere que ela foi substituída por esta regra mais recente: **o painel mostra só três anos projetados; o horizonte longo fica fora do painel**.

O painel permite visualizar:
- Séries históricas (2002–2023) e projeções públicas (2024–2026) com intervalo de confiança de 95%
- Controle de exibição do horizonte do painel entre `1` e `3` anos projetados
- Saídas técnicas complementares em planilhas separadas para `h=3` e `h=8`
- PIB nominal, VAB total, impostos, PIB real acumulado e deflator implícito acumulado (índices base 100 = 2002)
- VAB desagregado por macrossetor (agropecuária, indústria, serviços, administração pública)
- VAB desagregado por atividade econômica (12 atividades)
- Comparativo entre territórios
- Tabela interativa com todas as variáveis e fontes de dados (série principal, macrossetor, atividade)
- Filtro de anos de projeção exibidos (padrão: 3 anos, mínimo: 1 ano, máximo: 3 anos)
- Números formatados no padrão brasileiro (vírgula decimal, ponto milhar)
- Alternância modo claro/escuro via botão na barra superior

---

## Estrutura do Projeto

```
.
├── R/
│   ├── 01_leitura_dados.R       # Leitura e organização dos dados brutos
│   ├── 02_consistencia.R        # Verificação de identidades contábeis
│   ├── 03_projecao.R            # Modelagem e projeção (~1.089 séries, 7 modelos)
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
- **Horizonte público do painel:** 2024–2026
- **Horizonte técnico complementar:** 2024–2031, mantido apenas nas planilhas auxiliares
- **Cobertura:** 27 UFs, 5 regiões geográficas e Brasil (33 territórios)
- **Variáveis modeladas:** índices de volume e preço por atividade/macrossetor, log dos impostos

### Modelos de Projeção

Para cada série temporal (~1.089 no total), o script `03_projecao.R` seleciona automaticamente o melhor entre **7 modelos** via validação cruzada two-stage com janela expansiva (*expanding window CV*) para h=1, h=2 e h=3 simultaneamente (mínimo de 15 observações de treino):

| Sigla | Modelo | Descrição |
|-------|--------|-----------|
| `RW` | Passeio aleatório com drift | Tendência linear simples como linha de base |
| `ARMA` | Média móvel autorregressiva | Dependência linear de curto prazo (d=0) |
| `ARIMA` | ARIMA automático | Diferenciação + seleção por AIC |
| `ETS` | Suavização exponencial | Nível, tendência e sazonalidade adaptativa |
| `ETS-A` | ETS com tendência amortecida | Crescimento desacelerando no horizonte |
| `THETA` | Método Theta | Combinação de regressão linear e suavização |
| `SSM` | Modelo de espaço de estados | Filtro de Kalman (local linear trend) |

A seleção usa o menor **MASE ponderado** (*Mean Absolute Scaled Error* agregado com pesos 0,5 / 0,3 / 0,2 para h=1, h=2 e h=3). O CV opera em dois estágios: triagem rápida para todos os modelos e reavaliação precisa dos 3 finalistas com a mesma especificação usada na projeção final.

### Interpretação do Horizonte

- `2024–2026`: horizonte público do painel.
- `2024–2031`: horizonte técnico completo, mantido apenas nas planilhas auxiliares.
- O painel não usa mais a distinção operacional/exploratória na interface pública.

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
- Pacotes: `tidyverse`, `forecast`, `readxl`, `openxlsx`
- Dados brutos do IBGE em `base_bruta/` (não incluídos no repositório)

### Pipeline completo

```r
source("R/run_all.R")
```

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

### Preview local mínimo do painel

Sem alterar `painel/painel.qmd`, é possível abrir um preview local nativo do app com:

```powershell
.\preview_painel_local.ps1
```

Ou, se preferir chamar o R diretamente:

```powershell
& "C:\Program Files\R\R-4.4.0\bin\Rscript.exe" .\preview_painel_local.R
```

Esse helper reaproveita o bloco `shinylive-r` de `painel/painel.qmd`, mas serve `painel/data/` e `painel/metodologia.html` localmente via `shiny`, sem modificar o arquivo do painel.

---

## Outputs Gerados

| Arquivo/Pasta | Conteúdo |
|---------------|----------|
| `output/tabelas/projecoes_pib_estadual.xlsx` | Tabelas com projeções (9 abas) |
| `output/tabelas/projecoes_painel_h3.xlsx` | Cópia estrutural da planilha técnica, limitada ao horizonte público projetado (2024–2026) |
| `output/tabelas/projecoes_painel_h8.xlsx` | Planilha técnica de referência com o horizonte projetado completo usado fora do painel |
| `output/graficos/` | Gráficos PNG por variável e por território |
| `painel/data/serie_principal.csv` | Séries históricas + projeções públicas até 2026, 5 variáveis, IC 95% |
| `painel/data/vab_macrossetor.csv` | VAB histórico + projeções públicas até 2026 por macrossetor, IC 95% |
| `painel/data/vab_atividade.csv` | VAB histórico + projeções públicas até 2026 por atividade, IC 95% |
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
