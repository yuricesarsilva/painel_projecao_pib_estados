# Progresso do Projeto — Projeções PIBs Estaduais

## Etapa 0 — Planejamento e configuração

**O que foi feito:**
- Definido o escopo do projeto: projetar PIB nominal, VAB nominal (total e por atividade), impostos líquidos de subsídios, deflatores, taxa de crescimento real e VAB por 4 macrossetores para 27 UFs + 5 regiões + Brasil, com restrições de agregação contábil obrigatórias.
- Criado `plano_projeto.md` com objetivo, variáveis, macrossetores, fontes de dados e estrutura proposta de scripts.
- Criado repositório GitHub `yuricesarsilva/painel_projecao_pib_estados` (privado).
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

## Etapa 8 — Outputs completos: todos os territórios, IC 95%, todas as séries

**O que foi feito:**
- Modificado `R/03_projecao.R` para salvar `dados/vab_macro_hist.rds` com a série
  histórica (2002–2023) de VAB nominal, idx_volume e idx_preco por macrossetor × geo,
  necessária para os gráficos das séries brutas modeladas.
- Reescrito `R/05_output.R` completamente com cobertura total de outputs:

**Intervalos de confiança (IC 95%) calculados para:**
- VAB por macrossetor: propaga CI dos índices de volume e preço (`idx_vol_lo95/hi95`,
  `idx_prc_lo95/hi95`) já gravados em `vab_macro_reconciliado.rds`; aplica fator de
  reconciliação de cada macrossetor.
- VAB total: soma dos CI dos macrossetores.
- Impostos: `exp(lo95/hi95 do log_impostos)` × fator_ajuste de reconciliação.
- PIB nominal: `pib_ci = vab_ci + impostos_ci`.
- Crescimento real: média ponderada dos `idx_vol_lo95/hi95` com pesos do VAB 2023.

**Nova aba Excel — `Intervalos_Confianca`:**
- Formato longo: Território, Ano, Variável, Ponto_central, LI_95%, LS_95%.
- Cobre: pib_nominal, vab_nominal_total, impostos_nominal, cresc_real_pib_pct,
  vab_agropecuaria, vab_industria, vab_adm_publica, vab_servicos.
- Todos os 33 territórios × 8 anos projetados.

**Aba VAB_macrossetor atualizada:** inclui agora histórico 2002–2023 + projetado
2024–2031 (antes só tinha projetado).

**Gráficos — estrutura completamente reformulada:**

| Diretório | Conteúdo | Arquivos |
|-----------|----------|---------|
| `output/graficos/todas_geos/` | 1 plot por variável, todos os 33 territórios facetados com IC 95% | 9 |
| `output/graficos/por_geo/` | 1 plot por território com 9 painéis: PIB, VAB, impostos, cresc. real, deflator, VAB por 4 macrossetores | 33 |
| `output/graficos/series_brutas/` | Séries brutas modeladas (idx_volume e idx_preco por macrossetor + log_impostos) com CI 95%, todos os geos facetados | 9 |
| `output/graficos/` | 5 gráficos de resumo atualizados (CI adicionado onde aplicável) | 5 |

**Total de arquivos de gráfico: ~56 PNGs.**

**Novo output gerado:**

| Arquivo | Conteúdo |
|---------|----------|
| `dados/vab_macro_hist.rds` | VAB histórico por macrossetor × geo × ano (2002–2023) |

**Arquivos modificados:** `R/03_projecao.R`, `R/05_output.R`

---

## Etapa 7 — Tabela de seleção de modelos no output

**O que foi feito:**
- Modificado `R/03_projecao.R` (Parte 6) para capturar os parâmetros ótimos de cada
  modelo ajustado durante a projeção final, via `fc$method` (retornado pelos objetos
  de forecast do pacote `forecast`). Parâmetros incluem a ordem ARIMA(p,d,q),
  tipo ETS(e,t,s), estrutura NNAR(p,k), etc.
- Adicionado bloco ao final da Parte 6 que salva `dados/params_modelos.rds`:
  uma linha por série com geo, macrossetor, variável, modelo selecionado,
  parâmetros, MASE e RMSE.
- Modificado `R/05_output.R` para carregar `params_modelos.rds` e gerar a aba
  `Selecao_Modelos` no Excel, com rótulos legíveis para variável e macrossetor,
  ordenada por unidade geográfica → macrossetor → variável.
- Criado `CLAUDE.md` com instruções permanentes para Claude: atualizar `progresso.md`
  e fazer commit + push após cada alteração no projeto.

**Novo output gerado:**

| Arquivo | Conteúdo |
|---------|----------|
| `dados/params_modelos.rds` | Modelo, parâmetros, MASE e RMSE por série (~297 linhas) |

**Nova aba no Excel:**

| Aba | Conteúdo |
|-----|----------|
| `Selecao_Modelos` | Unidade geográfica, macrossetor, variável, modelo selecionado, parâmetros ótimos, MASE e RMSE — ~297 linhas |

**Arquivos modificados:** `R/03_projecao.R`, `R/05_output.R`
**Arquivos criados:** `CLAUDE.md`

---

## Etapa 9 — VAB por atividade econômica individual

**O que foi feito:**
- Implementada modelagem direta das 12 atividades IBGE (excluindo "total"), usando
  `idx_volume` e `idx_preco` provenientes de `conta_producao.rds` (Conta da Produção).
  As séries de atividade **não** são derivadas proporcionalmente dos macrossetores —
  cada atividade é modelada independentemente.

**Modificações em `R/03_projecao.R`:**
- Adicionado vetor `ATIVIDADES` com 12 códigos de atividade.
- `series_ativ` construída a partir de `cp` (conta_producao), pivotando
  `idx_volume` e `idx_preco` para formato longo.
- `serie_id` com prefixo `ativ__` para evitar colisão com macrossetores
  (ex.: `"Roraima|ativ__agropecuaria|idx_volume"`).
- Acrescentadas ~792 séries ao loop de CV expanding-window (~1.089 total).
- Nova Parte 7b: deriva `vab_nominal`, `vab_lo95`, `vab_hi95` por atividade,
  usando `vab_2023` × `cumprod(idx_volume × idx_preco)` com propagação de CI.
- Salvo `dados/vab_atividade_hist.rds` (histórico) e `dados/vab_atividade_proj.rds`.
- Coluna `atividade` adicionada a `params_modelos.rds` (NA para séries macro/impostos).

**Modificações em `R/04_reconciliacao.R`:**
- Nova Parte 6b: reconcilia VAB por atividade (mesma abordagem proporcional
  de 6a — soma das atividades → VAB total reconciliado).
- Aplica fator `fator_ativ` ao ponto central e a `vab_lo95`/`vab_hi95`.
- Verificação: desvio soma atividades vs. VAB total reconciliado < 0,00000001%.
- Salvo `dados/vab_atividade_reconciliada.rds`.

**Modificações em `R/05_output.R`:**
- Nova aba Excel **`VAB_atividade`**: macrossetor | atividade | ano | 33 geos;
  histórico 2002–2023 + projetado 2024–2031 com linha separadora.
- Aba **`Intervalos_Confianca`** estendida com IC 95% das 12 atividades
  (`variavel = vab_ativ_{atividade}`) para todos os 33 geos × 8 anos.
- Aba **`Selecao_Modelos`** atualizada: coluna "Setor/Atividade" distingue
  séries de macrossetor ("Macro: ...") de atividade ("Ativ: ...").
- 12 novos plots `output/graficos/todas_geos/vab_ativ_{atividade}.png`
  (todos os 33 geos facetados, ribbon IC 95%).
- 33 novos plots `output/graficos/por_geo_atividade/{geo}.png`
  (stacked-area VAB por atividade, histórico + projetado).

**Nota:** Deletar `dados/selecao_modelos.rds` antes de re-executar o pipeline
para que o CV seja refeito com as 1.089 séries completas.

**Outputs gerados:**

| Arquivo | Conteúdo |
|---------|----------|
| `dados/vab_atividade_hist.rds` | VAB histórico (val_corrente) por atividade × geo × ano (2002–2023) |
| `dados/vab_atividade_proj.rds` | VAB projetado + IC 95% por atividade × geo × ano (2024–2031) |
| `dados/vab_atividade_reconciliada.rds` | VAB atividade reconciliado + IC 95% (2024–2031) |

**Nova aba Excel e novos gráficos:**

| Saída | Conteúdo |
|-------|----------|
| `VAB_atividade` (aba Excel) | 12 atividades × 33 geos × 30 anos (histórico + projetado) |
| `Intervalos_Confianca` (aba Excel, estendida) | +12 variáveis vab_ativ_* × 33 geos × 8 anos |
| `output/graficos/todas_geos/vab_ativ_*.png` | 12 plots, todos os geos facetados com IC 95% |
| `output/graficos/por_geo_atividade/*.png` | 33 plots stacked-area por território |

**Arquivos modificados:** `R/03_projecao.R`, `R/04_reconciliacao.R`, `R/05_output.R`

---

## Etapa 10 — Painel interativo Quarto + shinylive (GitHub Pages)

**O que foi feito:**
- Criado painel interativo com Quarto Dashboard + shinylive, publicável no
  GitHub Pages sem servidor (R roda no browser via WebAssembly).

**Novos arquivos criados:**

| Arquivo | Função |
|---------|--------|
| `R/06_exportar_painel.R` | Exporta dados do pipeline para `painel/data/*.csv` (formato para o browser) |
| `painel/painel.qmd` | Painel Quarto Dashboard com bloco shinylive (UI + server Shiny completo) |
| `.github/workflows/publish-painel.yml` | GitHub Actions: renderiza o painel e publica na branch `gh-pages` |

**Arquivos modificados:** `R/run_all.R` (inclui script 06), `.gitignore` (exclui cache Quarto)

**Estrutura do painel (5 abas):**

| Aba | Conteúdo |
|-----|----------|
| Série Histórica | Linha histórico + projetado com ribbon IC 95%; filtros território + variável |
| Macrossetor | Stacked area (todos) ou linha com IC 95% (individual); filtro macrossetor |
| Atividade | Stacked area (todas) ou linha com IC 95% (individual); filtro atividade |
| Comparativo | Múltiplos territórios sobrepostos (sólido = histórico, tracejado = projetado) |
| Tabela | Dados numéricos com botões de exportação CSV/Excel |

**Sidebar global:** território, variável, toggle dia/noite (flatly/darkly).

**Fluxo de publicação:**
1. Rodar pipeline completo (`run_all.R`) localmente — gera `painel/data/*.csv`
2. Commitar os CSVs (`git add painel/data/`)
3. `git push` → GitHub Actions renderiza e publica em `gh-pages` automaticamente
4. URL pública: `https://yuricesarsilva.github.io/painel_projecao_pib_estados/`

**Pré-requisito local (uma vez):** instalar a extensão shinylive com:
```
cd painel
quarto add quarto-ext/shinylive
```
O diretório `_extensions/` gerado deve ser commitado junto com o painel.

**Dados exportados para o painel:**

| Arquivo CSV | Linhas aprox. | Conteúdo |
|-------------|---------------|----------|
| `painel/data/serie_principal.csv` | ~4.950 | 5 variáveis × 33 geos × 30 anos, com IC 95% |
| `painel/data/vab_macrossetor.csv` | ~3.960 | 4 macrossetores × 33 geos × 30 anos, com IC 95% |
| `painel/data/vab_atividade.csv` | ~11.880 | 12 atividades × 33 geos × 30 anos, com IC 95% |

---

## Etapa 11 â€” Planejamento da reforma do projeto

**O que foi feito:**
- Revisadas as instruÃ§Ãµes permanentes de `CLAUDE.md` antes de iniciar a nova rodada.
- Criado `plano_reforma.md` como documento-base da reforma do projeto.
- Consolidada uma proposta de reforma em camadas, priorizando:
  - preservaÃ§Ã£o da versÃ£o atual;
  - governanÃ§a do ambiente;
  - QA bloqueante;
  - refino metodolÃ³gico do baseline **univariado**;
  - transparÃªncia analÃ­tica e automaÃ§Ã£o.
- Registrado explicitamente que a camada com regressoras exÃ³genas (`xreg`) fica
  fora desta fase por falta de sÃ©ries auxiliares adequadas no momento.
- Reordenadas as frentes de trabalho para reduzir retrabalho:
  - primeiro infraestrutura, configuraÃ§Ã£o, logs e cache;
  - depois consistÃªncia bloqueante e governanÃ§a do horizonte;
  - depois reforma do CV e da famÃ­lia de modelos;
  - por fim diagnÃ³stico no painel, CI/CD e documentaÃ§Ã£o.

**Arquivos criados:** `plano_reforma.md`

**Complemento da etapa:**
- Criado `checklist_reforma.md` para acompanhamento operacional da execuÃ§Ã£o do plano.
- Estruturado o checklist por blocos, com caixas de marcaÃ§Ã£o para:
  - preservaÃ§Ã£o e baseline;
  - infraestrutura obrigatÃ³ria;
  - QA e governanÃ§a analÃ­tica;
  - reforma estatÃ­stica do baseline univariado;
  - transparÃªncia, automaÃ§Ã£o e documentaÃ§Ã£o.
- IncluÃ­da tambÃ©m uma seÃ§Ã£o separada de itens fora do escopo atual, deixando
  `xreg` e outras frentes metodolÃ³gicas futuras claramente registradas como adiadas.

---

## Etapa 12 â€” Bloco 1 da reforma: preservaÃ§Ã£o e baseline

**O que foi feito:**
- Criada a tag `v1.0-painel-atual` como ponto de restauraÃ§Ã£o da versÃ£o anterior Ã  reforma.
- Criada a branch `reforma-pipeline-univariado` para concentrar a execuÃ§Ã£o da reforma fora da linha principal.
- Criado `baseline_reforma.md` para documentar o baseline preservado, incluindo:
  - commit de referÃªncia;
  - comandos de restauraÃ§Ã£o;
  - descriÃ§Ã£o funcional do estado atual;
  - inventÃ¡rio dos CSVs versionados do painel com linhas e hashes SHA-256.
- Atualizado `checklist_reforma.md`, marcando o **Bloco 1** como concluÃ­do.
- Atualizado `CLAUDE.md` para incluir a regra permanente de manter `checklist_reforma.md`
  sincronizado sempre que a alteraÃ§Ã£o fizer parte da reforma.

**Arquivos criados:** `baseline_reforma.md`
**Arquivos modificados:** `CLAUDE.md`, `checklist_reforma.md`

**Baseline preservado:**

| ReferÃªncia | Valor |
|-----------|-------|
| Commit-base | `cb2b4b675eefc7cd9223211897de14e13e3377fa` |
| Tag | `v1.0-painel-atual` |
| Branch de reforma | `reforma-pipeline-univariado` |

**CSVs preservados do painel:**

| Arquivo | Linhas |
|---------|--------|
| `painel/data/serie_principal.csv` | 4.950 |
| `painel/data/vab_macrossetor.csv` | 3.960 |
| `painel/data/vab_atividade.csv` | 11.880 |

---

## Etapa 13 â€” Bloco 2 da reforma: infraestrutura obrigatÃ³ria

**O que foi feito:**
- Inicializado `renv` no projeto, com geraÃ§Ã£o de:
  - `.Rprofile`
  - `renv/activate.R`
  - `renv/settings.json`
  - `renv.lock`
- Hidratada a biblioteca do `renv` a partir dos pacotes jÃ¡ disponÃ­veis no ambiente local.
- Validado o estado do ambiente com `renv::status()`, retornando projeto consistente.
- Criado `R/config.R` para centralizar:
  - anos histÃ³ricos e de projeÃ§Ã£o;
  - horizonte de projeÃ§Ã£o;
  - `MIN_TRAIN`;
  - `SEED_GLOBAL`;
  - versÃ£o-alvo do R;
  - tolerÃ¢ncias base;
  - caminhos de log e cache.
- Criado `R/utils_cache.R` com funÃ§Ãµes de:
  - hash de arquivo;
  - hash de objeto R;
  - criaÃ§Ã£o de metadata de cache;
  - validaÃ§Ã£o de cache;
  - gravaÃ§Ã£o do cache com metadata.
- Criado `R/utils_logging.R` com funÃ§Ãµes para:
  - identificar branch e commit;
  - iniciar log estruturado da execuÃ§Ã£o;
  - registrar eventos;
  - salvar logs em `output/logs/`.

**AlteraÃ§Ãµes no pipeline:**
- `R/run_all.R`
  - passou a carregar `R/config.R` e `R/utils_logging.R`;
  - define `set.seed(SEED_GLOBAL)` no inÃ­cio;
  - registra branch, commit, seed e versÃ£o do R;
  - grava inÃ­cio/fim de cada script e falhas de execuÃ§Ã£o.
- `R/03_projecao.R`
  - removeu instalaÃ§Ã£o automÃ¡tica de `prophet`;
  - passou a usar `R/config.R`, `R/utils_cache.R` e `R/utils_logging.R`;
  - trocou o cache manual por cache validado por metadata/hashes;
  - passou a registrar warnings, erros e fallbacks na modelagem final.
- `R/05_output.R`
  - removeu instalaÃ§Ãµes em tempo de execuÃ§Ã£o de `openxlsx` e `RColorBrewer`;
  - passou a usar constantes centralizadas de `R/config.R`.
- `R/02_consistencia.R`, `R/04_reconciliacao.R` e `R/06_exportar_painel.R`
  - passaram a carregar `R/config.R`.

**AlteraÃ§Ã£o no workflow:**
- `.github/workflows/publish-painel.yml`
  - fixado `R 4.4.0`;
  - removida instalaÃ§Ã£o manual de pacotes;
  - adicionada restauraÃ§Ã£o do ambiente com `r-lib/actions/setup-renv@v2`.

**ValidaÃ§Ãµes realizadas:**
- `renv::status()` â€” projeto consistente.
- `parse()` de todos os scripts alterados â€” `parse_ok`.
- teste sintÃ©tico dos utilitÃ¡rios de cache e logging â€” `utils_ok`.

**Arquivos criados:** `.Rprofile`, `renv.lock`, `renv/activate.R`, `renv/settings.json`, `R/config.R`, `R/utils_cache.R`, `R/utils_logging.R`
**Arquivos modificados:** `R/run_all.R`, `R/02_consistencia.R`, `R/03_projecao.R`, `R/04_reconciliacao.R`, `R/05_output.R`, `R/06_exportar_painel.R`, `.github/workflows/publish-painel.yml`, `checklist_reforma.md`

---

## Etapa 14 â€” Bloco 3 da reforma: QA bloqueante e governanÃ§a do horizonte

**O que foi feito:**
- Reformulado `R/02_consistencia.R` para gerar um objeto `qa_status` com:
  - tabela de checagens;
  - desvio mÃ¡ximo por regra;
  - tolerÃ¢ncia por regra;
  - severidade (`fatal` ou `warning`);
  - status final `ok`.
- Classificadas como **fatais** as checagens de:
  - identidade `PIB = VAB + impostos`;
  - agregaÃ§Ã£o estados = regiÃ£o;
  - agregaÃ§Ã£o regiÃµes = Brasil.
- Mantidas como **warnings monitorados**:
  - soma das atividades = VAB total;
  - consistÃªncia dos impostos SIDRA.
- Ajustadas as tolerÃ¢ncias em `R/config.R` para evitar bloqueio por ruÃ­do numÃ©rico microscÃ³pico.
- Atualizado `R/run_all.R` para interromper o pipeline automaticamente quando `qa_status$ok == FALSE` apÃ³s `R/02_consistencia.R`.

**GovernanÃ§a do horizonte:**
- Definidos em `R/config.R`:
  - `ANO_OPERACIONAL_FIM = 2027`
  - `ANO_EXPLORATORIO_INI = 2028`
- Atualizado `R/06_exportar_painel.R` para exportar a coluna `horizonte` nos trÃªs CSVs do painel, com os valores:
  - `HistÃ³rico`
  - `Operacional`
  - `ExploratÃ³rio`
- Regenerados os CSVs versionados de `painel/data/`.

**AtualizaÃ§Ãµes de comunicaÃ§Ã£o:**
- `README.md`
  - passou a explicitar `2024â€“2027` como horizonte operacional e `2028â€“2031` como horizonte exploratÃ³rio.
- `painel/metodologia.html`
  - passou a reforÃ§ar essa distinÃ§Ã£o na seÃ§Ã£o de projeÃ§Ã£o, interpretaÃ§Ã£o e limitaÃ§Ãµes.
- `painel/painel.qmd`
  - passou a destacar visualmente o trecho exploratÃ³rio com faixa cinza;
  - adicionou aviso lateral sobre leitura recomendada do horizonte;
  - incluiu a informaÃ§Ã£o de horizonte na tabela;
  - ajustou subtÃ­tulos e captions para reforÃ§ar a diferenÃ§a entre leitura operacional e exploratÃ³ria.

**ValidaÃ§Ãµes realizadas:**
- `parse()` dos scripts centrais do Bloco 3 â€” `parse_ok`.
- ExecuÃ§Ã£o real de `R/02_consistencia.R` com `qa_status[['ok']] == TRUE`.
- ExecuÃ§Ã£o real de `R/06_exportar_painel.R` com exportaÃ§Ã£o concluÃ­da.
- ConfirmaÃ§Ã£o das colunas `horizonte` em:
  - `painel/data/serie_principal.csv`
  - `painel/data/vab_macrossetor.csv`
  - `painel/data/vab_atividade.csv`

**Arquivos modificados:** `R/config.R`, `R/02_consistencia.R`, `R/run_all.R`, `R/06_exportar_painel.R`, `painel/painel.qmd`, `painel/metodologia.html`, `README.md`, `checklist_reforma.md`

**Outputs atualizados:**

| Arquivo | Linhas | ObservaÃ§Ã£o |
|---------|--------|------------|
| `painel/data/serie_principal.csv` | 4.950 | coluna `horizonte` adicionada |
| `painel/data/vab_macrossetor.csv` | 3.960 | coluna `horizonte` adicionada |
| `painel/data/vab_atividade.csv` | 11.880 | coluna `horizonte` adicionada |

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

---

## Etapa 15 — Preview local mínimo após o Bloco 3

**Objetivo:**
- manter a base exatamente no estado pós-Bloco 3 da reforma e adicionar apenas o mínimo necessário para inspecionar o painel localmente.

**O que foi feito:**
- criada a branch `preview-local-minimo` a partir do commit `6f88613` (`Qualifica: torna o QA bloqueante e separa horizonte operacional`);
- criado `preview_painel_local.R`, que:
  - extrai o bloco `shinylive-r` de `painel/painel.qmd`;
  - substitui apenas em memória as URLs publicadas por recursos locais (`/data` e `/metodologia/metodologia.html`);
  - sobe o app com `shiny::runApp()` sem alterar `painel/painel.qmd`;
- criado `preview_painel_local.ps1` para facilitar a execução no Windows usando o `Rscript.exe` do R 4.4.0;
- atualizado `README.md` com as instruções de uso do preview local mínimo.

**Arquivos criados:** `preview_painel_local.R`, `preview_painel_local.ps1`
**Arquivos modificados:** `README.md`

**Resultado prático:**
- o painel pode ser inspecionado localmente nesta branch sem depender do GitHub Pages e sem introduzir mudanças estruturais no arquivo `painel/painel.qmd`.

---

## Etapa 16 — Limpeza dos avisos visuais temporários do preview

**Objetivo:**
- remover as telas vermelhas de diagnóstico que ficaram no `painel.qmd` após os testes do preview.

**O que foi feito:**
- removida a função temporária `render_plot_erro()` do `painel/painel.qmd`;
- restaurado o fluxo normal de `renderPlot()` nas quatro áreas gráficas:
  - `plot_serie`
  - `plot_macro`
  - `plot_ativ`
  - `plot_comp`
- mantida apenas a notificação legível de falha de carregamento dos CSVs (`data_load_error`), que continua útil no preview local.

**Arquivos modificados:** `painel/painel.qmd`

**Resultado prático:**
- o preview local deixa de exibir os placeholders vermelhos usados no diagnóstico anterior e volta a mostrar apenas o comportamento normal do painel.

---

## Etapa 17 — Redefinição agressiva do horizonte público do painel

**Objetivo:**
- restringir o produto público ao horizonte `h=3`, preservando o horizonte técnico completo `h=8` fora do painel.

**O que foi alterado até aqui:**
- `R/config.R`
  - adicionados `H_PAINEL = 3L` e `ANO_PAINEL_PROJ_FIM = 2026L`;
  - reclassificado o corte operacional para `2026` e o técnico complementar a partir de `2027`.
- `R/06_exportar_painel.R`
  - os CSVs em `painel/data/` passam a ser filtrados para o horizonte público do painel;
  - criada a saída técnica adicional `output/tabelas/projecoes_painel_h8.xlsx`, preservando o horizonte completo de projeção.
- `painel/painel.qmd`
  - o painel passa a trabalhar com `ANO_PROJ_FIM = 2026L`;
  - o cálculo do horizonte exibido foi fixado em `H_PAINEL`.
- `README.md`
  - adicionada seção explícita esclarecendo a separação entre painel público (`h=3`) e saída técnica (`h=8`);
  - atualizada a seção de outputs para documentar `projecoes_painel_h8.xlsx`.
- `painel/metodologia.html`
  - adicionada observação no topo informando que o painel público foi reduzido para `2024–2026`, mesmo quando o pipeline técnico segue até `2031`.
- `checklist_reforma.md`
  - marcadas as atualizações de `README.md` e `painel/metodologia.html`.

**Pendência operacional:**
- regenerar os CSVs do painel e a planilha técnica `h=8` localmente, pois as tentativas automáticas desta sessão ficaram instáveis no shell.

**Ajuste posterior solicitado pelo usuário:**
- o controle `Anos de projeção exibidos` do painel deve ir de `1` a `3`, e não ficar travado em `3`;
- a coluna `Horizonte` deixa de aparecer na tabela do painel;
- as saídas técnicas passam a incluir duas planilhas auxiliares:
  - `output/tabelas/projecoes_painel_h3.xlsx`
  - `output/tabelas/projecoes_painel_h8.xlsx`
