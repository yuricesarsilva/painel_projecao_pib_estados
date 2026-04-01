# Progresso do Projeto — Projeções PIBs Estaduais

## Etapa 0 — Planejamento e configuração

**O que foi feito:**
- Definido o escopo do projeto: projetar PIB nominal, VAB nominal (total e por atividade), impostos líquidos de subsídios, deflatores, taxa de crescimento real e VAB por 4 macrossetores para 27 UFs + 5 regiões + Brasil, com restrições de agregação contábil obrigatórias.
- Criado `plano_projeto.md` com objetivo, variáveis, macrossetores, fontes de dados e estrutura proposta de scripts.
- Criado repositório GitHub `yuricesarsilva/relatorio_projecao_pib_estados` (privado).
- Configurado git no diretório do projeto com `.gitignore` excluindo `base_bruta/`, `dados/` e `output/`.

**Arquivos criados:** `plano_projeto.md`, `.gitignore`

---

## Etapa 1 — Inspeção e diagnóstico dos dados

**O que foi feito:**
- Inspecionados todos os arquivos brutos em `base_bruta/` usando R (`readxl`).
- Mapeada a estrutura exata de cada tipo de arquivo (linhas de cabeçalho, linhas de dados, colunas).
- Confirmado que os dados são suficientes para todas as variáveis do projeto.
- Identificado e documentado: unidade monetária (R$ milhões nos Especiais, R$ mil no SIDRA), ano de referência do índice encadeado (2010), cobertura 2002–2023.
- Criado `diagnostico_dados.md` com estrutura completa, disponibilidade por variável e notas.

**Principais achados:**
- Conta da Produção: 33 arquivos × 13 atividades × 3 blocos (VBP, CI, VAB) × 6 colunas (ano, val_ano_ant, idx_volume, val_preco_ant, idx_preco, val_corrente).
- `Tabela19.xls` (Região Sudeste) tem bug nos nomes das abas — usa `Tabela1.x` em vez de `Tabela19.x`.
- SIDRA em R$ mil; Especiais em R$ milhões — requer conversão.
- Acre tem 10 NAs em `val_corrente` para 2002 em atividades de serviços — limitação do IBGE original.

**Arquivos criados:** `diagnostico_dados.md`

---

## Etapa 2 — Leitura e estruturação dos dados (`R/01_leitura_dados.R`)

**O que foi feito:**
- Criado script R que lê todas as fontes brutas e salva dois `.rds` em formato tidy em `dados/`.
- Implementadas 3 funções de leitura reutilizáveis:
  - `ler_especial_simples()` — para tab01–04 e SIDRA (wide, 33 entidades).
  - `ler_especial_atividade()` — para tab05 (wide com linha extra de categoria, 32 entidades).
  - `ler_conta_bloco()` — para um bloco (VBP/CI/VAB) da Conta da Produção, usando índice posicional de aba (contorna o bug do Tabela19.xls).
- Tabelas de referência `GEO_MAP` e `ATIV_MAP` embutidas no script.
- Correção de unidades: SIDRA dividido por 1.000 para ficar em R$ milhões.
- Imputação de impostos faltantes (tipicamente 2022–2023) via identidade contábil: `Impostos = PIB - VAB`, para pares geo×ano ausentes ou com NA no SIDRA.
- Verificações embutidas ao final: contagem de linhas, cobertura temporal, NAs esperados, comparação de unidades tab01 vs SIDRA.

**Correção aplicada (commit 22c3665):** Ao fazer `bind_rows` entre dados do SIDRA e impostos imputados, linhas com `valor = NA` do SIDRA eram mantidas, gerando duplicatas para os mesmos pares geo×ano. Corrigido filtrando `!is.na(valor)` antes do `bind_rows`.

**Outputs gerados:**

| Arquivo | Colunas | Linhas |
|---------|---------|--------|
| `dados/especiais.rds` | geo, geo_tipo, regiao, ano, variavel, atividade, valor | 12.056 |
| `dados/conta_producao.rds` | geo, geo_tipo, regiao, atividade, bloco, ano, val_ano_ant, idx_volume, val_preco_ant, idx_preco, val_corrente | 28.314 |

**Arquivos criados:** `R/01_leitura_dados.R`

---

## Etapa 3 — Verificação de consistência contábil (`R/02_consistencia.R`)

**O que foi feito:**
- Criado script que verifica 5 identidades contábeis nos dados históricos (2002–2023).
- Resultados salvos em `dados/consistencia.rds`.

**Resultados:**

| Checagem | Desvio máximo | Resultado |
|----------|--------------|-----------|
| 1. PIB = VAB + Impostos | ~0,000002% | ✅ Satisfeita (arredondamento numérico) |
| 2. Soma dos estados = PIB da região | ~10⁻¹³% | ✅ Satisfeita (ponto flutuante) |
| 3. Soma das regiões = PIB Brasil | ~10⁻¹³% | ✅ Satisfeita (ponto flutuante) |
| 4. Soma das atividades = VAB total | -64% em Acre 2002 | ⚠️ Único caso — NAs já conhecidos do IBGE |
| 5. Impostos: consistência e origem (SIDRA vs. imputado) | — | ✅ Identifica anos imputados e valida desvios |

**Nota:** O desvio de Acre 2002 é causado pelos 10 NAs em `val_corrente` identificados na Etapa 1. A soma das atividades fica incompleta, mas o total do IBGE está correto. Não é erro do pipeline.

**Arquivos criados:** `R/02_consistencia.R`

---

## Etapa 4 — Modelagem e projeção (`R/03_projecao.R`)

**O que foi feito:**
- Criado script de projeção com validação cruzada e derivações contábeis.
- Horizonte: 2024–2031 (8 anos).
- Séries modeladas: índices de volume e preço do VAB por macrossetor × geo, e log(impostos) por geo — total de ~1.000+ séries.
- 4 modelos candidatos por série: **ETS**, **SARIMA** (via `auto.arima`), **Prophet** e **SSM** (StructTS — local linear trend via filtro de Kalman).
- Seleção por validação cruzada com janela mínima de 15 anos de treino; métrica RMSE.
- Derivações contábeis pós-projeção:
  - VAB nominal total = agregação dos macrossetores projetados.
  - PIB nominal = VAB nominal + impostos nominais.
  - Deflator do PIB recalculado com base nos índices encadeados.
- Mapeamento de macrossetores: Agropecuária, Indústria (4 atividades), Adm. Pública e Serviços (6 atividades).

**Outputs gerados:**

| Arquivo | Conteúdo |
|---------|----------|
| `dados/selecao_modelos.rds` | Modelo selecionado e RMSE por série |
| `dados/projecoes_brutas.rds` | Projeções brutas de cada série |
| `dados/projecoes_derivadas.rds` | PIB nominal, VAB, impostos e deflator derivados por geo × ano |
| `dados/vab_macrossetor_proj.rds` | VAB nominal projetado por macrossetor × geo × ano |

**Arquivos criados:** `R/03_projecao.R`

---

## Etapa 5 — Reconciliação top-down (`R/04_reconciliacao.R`)

**O que foi feito:**
- Criado script que impõe as restrições de agregação contábil às projeções individuais.
- Método: benchmarking proporcional top-down:
  - Brasil (âncora) → regiões ajustadas → estados ajustados dentro de cada região.
  - VAB e impostos escalonados pela mesma razão do PIB, preservando `PIB = VAB + Impostos`.
  - Deflator recalculado pós-reconciliação mantendo a taxa de crescimento real inalterada.
- VAB por macrossetor reconciliado para bater com o VAB total reconciliado.
- Verificações de consistência ao final: desvio máximo 0% em todas as identidades.

**Outputs gerados:**

| Arquivo | Conteúdo |
|---------|----------|
| `dados/projecoes_reconciliadas.rds` | PIB, VAB, impostos, deflator e fator de ajuste por geo × ano (264 linhas) |
| `dados/vab_macro_reconciliado.rds` | VAB por macrossetor reconciliado (1.056 linhas) |

**Arquivos criados:** `R/04_reconciliacao.R`

---

## Etapa 6 — Geração de outputs (`R/05_output.R`)

**O que foi feito:**
- Criado script que gera tabelas Excel e gráficos a partir das projeções reconciliadas.
- Tabela Excel com 6 abas: PIB_nominal, VAB_nominal, Impostos_nominais, Cresc_real_PIB, Deflator_PIB, VAB_macrossetor.
- Formatação diferenciada para linhas de Brasil e regiões (totalizadores).
- 5 gráficos PNG: PIB nominal Brasil, crescimento real por regiões, PIB nominal Roraima, fatores de ajuste, participação dos estados no PIB.

**Outputs gerados:**

| Arquivo | Conteúdo |
|---------|----------|
| `output/tabelas/projecoes_pib_estadual.xlsx` | 6 abas com série histórica + projeções 2024–2031 |
| `output/graficos/pib_nominal_brasil.png` | Evolução do PIB nominal do Brasil |
| `output/graficos/cresc_real_regioes.png` | Crescimento real por regiões |
| `output/graficos/pib_nominal_roraima.png` | PIB nominal de Roraima |
| `output/graficos/fatores_ajuste.png` | Distribuição dos fatores de ajuste |
| `output/graficos/participacao_pib_estados.png` | Participação dos estados no PIB |

**Arquivos criados:** `R/05_output.R`

---

## Pipeline completo (`run_all.R`)

- Criado `run_all.R` para execução sequencial dos 5 scripts com tratamento de erros e cronometragem por etapa.
- Cache automático: se `selecao_modelos.rds` já existir, o script 03 pula a validação cruzada.

---

## Status das etapas

- [x] `R/01_leitura_dados.R` — leitura e estruturação dos dados brutos
- [x] `R/02_consistencia.R` — verificar identidades contábeis nos dados históricos
- [x] `R/03_projecao.R` — modelos de projeção por variável e setor
- [x] `R/04_reconciliacao.R` — garantir restrições de agregação nas projeções
- [x] `R/05_output.R` — gerar tabelas e gráficos de resultado
- [x] `run_all.R` — orquestrador do pipeline completo
