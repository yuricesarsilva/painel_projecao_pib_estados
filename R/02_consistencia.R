library(tidyverse)

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
# Salvar resultado das checagens
# ==============================================================================

dir.create("dados", showWarnings = FALSE)
saveRDS(
  list(
    pib_vab_impostos   = check1,
    agregacao_regional = check2,
    agregacao_nacional = check3,
    vab_atividades     = check4
  ),
  "dados/consistencia.rds"
)

cat("\nResultados salvos em dados/consistencia.rds\n")
