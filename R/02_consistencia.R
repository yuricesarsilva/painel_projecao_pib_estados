source("R/config.R", local = FALSE)

library(tidyverse)

# ==============================================================================
# 02_consistencia.R
#
# Verifica identidades contábeis nos dados históricos (2002–2023).
# Não gera projeções; serve como camada de validação da base de dados.
#
# Checagens realizadas:
#   1. PIB = VAB + Impostos          (para cada geo × ano)
#   2. Soma dos estados = região     (para cada região × ano)
#   3. Soma das regiões = Brasil     (para cada ano)
#   4. Soma das atividades = VAB total (Conta da Produção, excluindo "total")
#   5. Consistência dos impostos: SIDRA vs. imputados (PIB − VAB)
#
# Nota: Acre × 2002 apresenta NAs em val_corrente para algumas atividades
# de serviços — limitação do arquivo IBGE original, não é erro do pipeline.
# Isso causa desvio de ~−64% na Checagem 4 para esse par geo×ano.
#
# Entradas:  dados/especiais.rds, dados/conta_producao.rds
# Saídas:    dados/consistencia.rds
# ==============================================================================

# ==============================================================================
# Carrega dados
# ==============================================================================

esp <- readRDS("dados/especiais.rds")

# Pivot para wide: uma coluna por variável principal
base <- esp |>
  filter(variavel %in% c("pib_nominal", "vab_nominal", "impostos_nominal")) |>
  select(geo, geo_tipo, regiao, ano, variavel, valor) |>
  pivot_wider(names_from = variavel, values_from = valor)

# ==============================================================================
# Checagem 1 — Identidade PIB = VAB + Impostos
# ==============================================================================

check1 <- base |>
  mutate(
    pib_recalc   = vab_nominal + impostos_nominal,
    desvio_abs   = pib_nominal - pib_recalc,
    desvio_rel   = desvio_abs / pib_nominal * 100
  )

# Resumo geral
cat("=== Checagem 1: PIB = VAB + Impostos ===\n")
cat("Desvio relativo (%) — resumo:\n")
check1 |>
  summarise(
    min   = min(desvio_rel,  na.rm = TRUE),
    p25   = quantile(desvio_rel, 0.25, na.rm = TRUE),
    media = mean(desvio_rel, na.rm = TRUE),
    p75   = quantile(desvio_rel, 0.75, na.rm = TRUE),
    max   = max(desvio_rel,  na.rm = TRUE),
    n_acima_1pct = sum(abs(desvio_rel) > 1, na.rm = TRUE)
  ) |>
  print()

# Casos com desvio > 1%
grandes_desvios1 <- check1 |>
  filter(abs(desvio_rel) > 1) |>
  arrange(desc(abs(desvio_rel))) |>
  select(geo, ano, pib_nominal, vab_nominal, impostos_nominal, desvio_abs, desvio_rel)

if (nrow(grandes_desvios1) > 0) {
  cat("\nCasos com |desvio| > 1%:\n")
  print(grandes_desvios1, n = 20)
} else {
  cat("\nNenhum caso com |desvio| > 1%. Identidade satisfeita.\n")
}

# ==============================================================================
# Checagem 2 — Soma dos estados = PIB da região
# ==============================================================================

# PIB dos estados por região e ano
soma_estados <- base |>
  filter(geo_tipo == "estado") |>
  group_by(regiao, ano) |>
  summarise(pib_soma_estados = sum(pib_nominal, na.rm = TRUE), .groups = "drop")

# PIB das regiões (direto do dado)
pib_regioes <- base |>
  filter(geo_tipo == "regiao") |>
  select(regiao = geo, ano, pib_regiao = pib_nominal)

check2 <- soma_estados |>
  left_join(pib_regioes, by = c("regiao", "ano")) |>
  mutate(
    desvio_abs = pib_soma_estados - pib_regiao,
    desvio_rel = desvio_abs / pib_regiao * 100
  )

cat("\n=== Checagem 2: Soma dos estados = PIB da região ===\n")
cat("Desvio relativo (%) — resumo:\n")
check2 |>
  summarise(
    min   = min(desvio_rel,  na.rm = TRUE),
    p25   = quantile(desvio_rel, 0.25, na.rm = TRUE),
    media = mean(desvio_rel, na.rm = TRUE),
    p75   = quantile(desvio_rel, 0.75, na.rm = TRUE),
    max   = max(desvio_rel,  na.rm = TRUE),
    n_acima_1pct = sum(abs(desvio_rel) > 1, na.rm = TRUE)
  ) |>
  print()

grandes_desvios2 <- check2 |>
  filter(abs(desvio_rel) > 1) |>
  arrange(desc(abs(desvio_rel)))

if (nrow(grandes_desvios2) > 0) {
  cat("\nCasos com |desvio| > 1%:\n")
  print(grandes_desvios2, n = 20)
} else {
  cat("\nNenhum caso com |desvio| > 1%. Agregação regional satisfeita.\n")
}

# ==============================================================================
# Checagem 3 — Soma das regiões = PIB Brasil
# ==============================================================================

soma_regioes <- base |>
  filter(geo_tipo == "regiao") |>
  group_by(ano) |>
  summarise(pib_soma_regioes = sum(pib_nominal, na.rm = TRUE), .groups = "drop")

pib_brasil <- base |>
  filter(geo_tipo == "brasil") |>
  select(ano, pib_brasil = pib_nominal)

check3 <- soma_regioes |>
  left_join(pib_brasil, by = "ano") |>
  mutate(
    desvio_abs = pib_soma_regioes - pib_brasil,
    desvio_rel = desvio_abs / pib_brasil * 100
  )

cat("\n=== Checagem 3: Soma das regiões = PIB Brasil ===\n")
print(check3 |> select(ano, pib_soma_regioes, pib_brasil, desvio_abs, desvio_rel), n = 25)

if (all(abs(check3$desvio_rel) < 1, na.rm = TRUE)) {
  cat("\nAgregação nacional satisfeita (todos os desvios < 1%).\n")
} else {
  cat("\nATENÇÃO: desvios acima de 1% encontrados.\n")
}

# ==============================================================================
# Checagem 4 — VAB: soma das atividades = VAB total (Conta da Produção)
# ==============================================================================

cp <- readRDS("dados/conta_producao.rds")

# VAB corrente por atividade (excluindo "total")
vab_ativ <- cp |>
  filter(bloco == "vab", atividade != "total") |>
  group_by(geo, geo_tipo, regiao, ano) |>
  summarise(vab_soma_ativ = sum(val_corrente, na.rm = TRUE), .groups = "drop")

# VAB total da Conta da Produção
vab_total_cp <- cp |>
  filter(bloco == "vab", atividade == "total") |>
  select(geo, ano, vab_total = val_corrente)

check4 <- vab_ativ |>
  left_join(vab_total_cp, by = c("geo", "ano")) |>
  mutate(
    desvio_abs = vab_soma_ativ - vab_total,
    desvio_rel = desvio_abs / vab_total * 100
  )

cat("\n=== Checagem 4: Soma das atividades = VAB total (Conta da Produção) ===\n")
cat("Desvio relativo (%) — resumo:\n")
check4 |>
  summarise(
    min   = min(desvio_rel,  na.rm = TRUE),
    p25   = quantile(desvio_rel, 0.25, na.rm = TRUE),
    media = mean(desvio_rel, na.rm = TRUE),
    p75   = quantile(desvio_rel, 0.75, na.rm = TRUE),
    max   = max(desvio_rel,  na.rm = TRUE),
    n_acima_1pct = sum(abs(desvio_rel) > 1, na.rm = TRUE)
  ) |>
  print()

grandes_desvios4 <- check4 |>
  filter(abs(desvio_rel) > 1) |>
  arrange(desc(abs(desvio_rel)))

if (nrow(grandes_desvios4) > 0) {
  cat("\nCasos com |desvio| > 1%:\n")
  print(grandes_desvios4 |> select(geo, ano, vab_soma_ativ, vab_total, desvio_rel), n = 20)
} else {
  cat("\nNenhum caso com |desvio| > 1%. Soma das atividades satisfeita.\n")
}

# ==============================================================================
# Checagem 5 — Impostos: consistência e detecção de anos imputados
# ==============================================================================
# Impostos imputados em 01_leitura_dados.R via PIB - VAB produzem desvio
# exatamente zero. Desvios não nulos indicam dado original do SIDRA — verifica-
# se estão dentro de tolerância aceitável (diferenças de arredondamento).

check5 <- base |>
  filter(!is.na(pib_nominal), !is.na(vab_nominal), !is.na(impostos_nominal)) |>
  mutate(
    impostos_recalc = pib_nominal - vab_nominal,
    desvio_abs      = impostos_nominal - impostos_recalc,
    desvio_rel      = desvio_abs / impostos_nominal * 100,
    # Valores imputados têm desvio praticamente zero (diferença < R$ 0,01 mi)
    fonte           = if_else(abs(desvio_abs) < 0.01, "imputado (PIB-VAB)", "SIDRA")
  )

anos_imputados <- check5 |>
  filter(fonte == "imputado (PIB-VAB)", geo_tipo == "brasil") |>
  pull(ano) |>
  sort() |>
  unique()

cat("\n=== Checagem 5: Impostos — Consistência e origem dos dados ===\n")
cat("Anos com impostos imputados (PIB - VAB):",
    if (length(anos_imputados) > 0) paste(anos_imputados, collapse = ", ")
    else "nenhum", "\n")

cat("\nDistribuição das fontes por ano (nível Brasil):\n")
check5 |>
  filter(geo_tipo == "brasil") |>
  select(ano, impostos_nominal, impostos_recalc, desvio_abs, desvio_rel, fonte) |>
  arrange(ano) |>
  print(n = 30)

cat("\nDesvio impostos_nominal vs. (PIB - VAB) — apenas anos SIDRA:\n")
sidra_check <- check5 |> filter(fonte == "SIDRA")

if (nrow(sidra_check) > 0) {
  sidra_check |>
    summarise(
      min  = round(min(desvio_rel,  na.rm = TRUE), 4),
      med  = round(mean(desvio_rel, na.rm = TRUE), 4),
      max  = round(max(desvio_rel,  na.rm = TRUE), 4),
      n_acima_1pct = sum(abs(desvio_rel) > 1, na.rm = TRUE)
    ) |>
    print()

  grandes_desvios5 <- sidra_check |>
    filter(abs(desvio_rel) > 1) |>
    arrange(desc(abs(desvio_rel))) |>
    select(geo, ano, impostos_nominal, impostos_recalc, desvio_abs, desvio_rel)

  if (nrow(grandes_desvios5) > 0) {
    cat("\nCasos com |desvio| > 1% (SIDRA vs. PIB - VAB):\n")
    print(grandes_desvios5, n = 20)
  } else {
    cat("Nenhum desvio > 1% nos anos com dados SIDRA.\n")
  }
} else {
  cat("Todos os anos foram imputados (sem dados SIDRA para comparação).\n")
}

# ==============================================================================
# Salvar resultado das checagens
# ==============================================================================

dir.create("dados", showWarnings = FALSE)
saveRDS(
  list(
    pib_vab_impostos        = check1,
    agregacao_regional      = check2,
    agregacao_nacional      = check3,
    vab_atividades          = check4,
    impostos_consistencia   = check5
  ),
  "dados/consistencia.rds"
)

cat("\nResultados salvos em dados/consistencia.rds\n")
