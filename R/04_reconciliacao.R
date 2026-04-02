library(tidyverse)

# ==============================================================================
# 04_reconciliacao.R
#
# Reconcilia as projeções individuais para impor as restrições de agregação:
#   1. soma(estados da região) = PIB da região   (para cada uma das 5 regiões)
#   2. soma(regiões)           = PIB Brasil
#   3. PIB = VAB + impostos                      (garantido por construção; verificado)
#
# Método: benchmarking proporcional top-down
#   Brasil (âncora) → regiões ajustadas → estados ajustados dentro de cada região
#   Os subcomponentes (VAB total e impostos) são escalonados pela mesma razão
#   do PIB, preservando a identidade contábil PIB = VAB + Impostos em todos
#   os níveis geográficos.
#
# Parte 6  — Reconciliação VAB por macrossetor:
#   Dentro de cada geo × ano, escala os macrossetores para que a soma bata
#   com o VAB total reconciliado (fator proporcional único por geo × ano).
#
# Parte 6b — Reconciliação VAB por atividade individual:
#   Mesma lógica da Parte 6, aplicada às 12 atividades individuais.
#   O fator é aplicado também a vab_lo95 e vab_hi95, preservando os IC 95%.
#   Só executa se dados/vab_atividade_proj.rds existir.
#
# Parte 4  — Deflator reconciliado:
#   tx_cresc_pib_real é mantida inalterada (índices encadeados não são
#   aditivos espacialmente). O deflator é recalculado pós-reconciliação
#   usando o PIB nominal reconciliado e o índice de volume acumulado.
#
# Entradas:  dados/projecoes_derivadas.rds
#            dados/vab_macrossetor_proj.rds
#            dados/vab_atividade_proj.rds   (opcional)
#            dados/especiais.rds
# Saídas:    dados/projecoes_reconciliadas.rds
#            dados/vab_macro_reconciliado.rds
#            dados/vab_atividade_reconciliada.rds  (se atividade_proj existir)
# ==============================================================================

# ==============================================================================
# Parte 0 — Parâmetros
# ==============================================================================

ANO_FIM <- 2023L

# ==============================================================================
# Parte 1 — Carregar dados
# ==============================================================================

message("Carregando dados...")
proj      <- readRDS("dados/projecoes_derivadas.rds")
vab_macro <- readRDS("dados/vab_macrossetor_proj.rds")
esp       <- readRDS("dados/especiais.rds")

pib_2023 <- esp |>
  filter(variavel == "pib_nominal", ano == ANO_FIM) |>
  select(geo, pib_2023 = valor)

# Separar os três níveis geográficos
br   <- proj |> filter(geo_tipo == "brasil")
regs <- proj |> filter(geo_tipo == "regiao")
ufs  <- proj |> filter(geo_tipo == "estado")

message("Séries carregadas: Brasil=", nrow(br) / length(unique(proj$ano)),
        " reg=", nrow(regs) / length(unique(proj$ano)),
        " UFs=", nrow(ufs) / length(unique(proj$ano)),
        "  ×  ", length(unique(proj$ano)), " anos")

# ==============================================================================
# Parte 2 — Reconciliação proporcional top-down do PIB nominal
# ==============================================================================
# O PIB do Brasil é o âncora (projeção individual mais robusta).
# Cada região é escalonada para que soma(regiões) = Brasil.
# Cada estado é escalonado para que soma(estados da região) = região reconciliada.

message("Reconciliando PIB nominal (top-down)...")

## 2a. Fator região → Brasil ------------------------------------------------
soma_regs <- regs |>
  group_by(ano) |>
  summarise(soma_regs_bruta = sum(pib_nominal, na.rm = TRUE), .groups = "drop")

ajuste_reg <- br |>
  select(ano, pib_brasil = pib_nominal) |>
  left_join(soma_regs, by = "ano") |>
  mutate(fator_reg = pib_brasil / soma_regs_bruta) |>
  select(ano, fator_reg)

regs_rec <- regs |>
  left_join(ajuste_reg, by = "ano") |>
  mutate(pib_nominal_rec = pib_nominal * fator_reg)

## 2b. Fator estado → região reconciliada ------------------------------------
soma_ufs <- ufs |>
  group_by(regiao, ano) |>
  summarise(soma_ufs_bruta = sum(pib_nominal, na.rm = TRUE), .groups = "drop")

# Cada UF tem `regiao` = nome da região; o PIB reconciliado da região está em
# regs_rec com `geo` = nome da região → join por regiao ↔ geo
ajuste_uf <- regs_rec |>
  select(regiao = geo, ano, pib_reg_rec = pib_nominal_rec) |>
  left_join(soma_ufs, by = c("regiao", "ano")) |>
  mutate(fator_uf = pib_reg_rec / soma_ufs_bruta) |>
  select(regiao, ano, fator_uf)

ufs_rec <- ufs |>
  left_join(ajuste_uf, by = c("regiao", "ano")) |>
  mutate(pib_nominal_rec = pib_nominal * fator_uf)

## 2c. Brasil: âncora, sem ajuste -------------------------------------------
br_rec <- br |>
  mutate(pib_nominal_rec = pib_nominal,
         fator_reg = 1,
         fator_uf  = NA_real_)

# ==============================================================================
# Parte 3 — Escalonar VAB total e impostos (mantém PIB = VAB + impostos)
# ==============================================================================
# vab_rec = vab_orig × (pib_rec / pib_orig)   [mesma razão = fator de ajuste]
# imp_rec = imp_orig × (pib_rec / pib_orig)
# → vab_rec + imp_rec = (vab_orig + imp_orig) × fator = pib_orig × fator = pib_rec ✓

escalonar_subcomp <- function(df) {
  df |>
    mutate(
      fator_nominal         = pib_nominal_rec / pib_nominal,
      vab_nominal_total_rec = vab_nominal_total * fator_nominal,
      impostos_nominal_rec  = impostos_nominal  * fator_nominal
    )
}

br_rec   <- escalonar_subcomp(br_rec)
regs_rec <- escalonar_subcomp(regs_rec)
ufs_rec  <- escalonar_subcomp(ufs_rec)

# ==============================================================================
# Parte 4 — Recalcular deflator do PIB pós-reconciliação
# ==============================================================================
# Mantemos tx_cresc_pib_real inalterada (dimensão de volume não é reconciliada
# espacialmente — índices encadeados não são aditivos).
# Deflator reconciliado = (PIB_rec_t / PIB_2023) / vol_idx_base2023(t)

vol_idx <- proj |>
  arrange(geo, ano) |>
  group_by(geo) |>
  mutate(vol_idx_base2023 = cumprod(1 + tx_cresc_pib_real)) |>
  ungroup() |>
  select(geo, ano, vol_idx_base2023)

calcular_deflator_rec <- function(df) {
  df |>
    left_join(pib_2023,  by = "geo") |>
    left_join(vol_idx,   by = c("geo", "ano")) |>
    mutate(
      deflator_pib_rec = if_else(
        vol_idx_base2023 > 0 & !is.na(vol_idx_base2023),
        (pib_nominal_rec / pib_2023) / vol_idx_base2023,
        NA_real_
      )
    ) |>
    select(-pib_2023, -vol_idx_base2023)
}

br_rec   <- calcular_deflator_rec(br_rec)
regs_rec <- calcular_deflator_rec(regs_rec)
ufs_rec  <- calcular_deflator_rec(ufs_rec)

# ==============================================================================
# Parte 5 — Montar tabela final reconciliada
# ==============================================================================

padronizar <- function(df) {
  fator_col <- if ("fator_uf" %in% names(df) && !all(is.na(df$fator_uf))) {
    "fator_uf"
  } else {
    "fator_reg"
  }
  df |>
    transmute(
      geo, geo_tipo, regiao, ano,
      pib_nominal       = pib_nominal_rec,
      vab_nominal_total = vab_nominal_total_rec,
      impostos_nominal  = impostos_nominal_rec,
      tx_cresc_pib_real,                      # inalterada (dimensão real)
      deflator_pib      = deflator_pib_rec,
      fator_ajuste      = .data[[fator_col]]
    )
}

projecoes_rec <- bind_rows(
  padronizar(br_rec),
  padronizar(regs_rec),
  padronizar(ufs_rec)
) |>
  arrange(geo_tipo, geo, ano)

saveRDS(projecoes_rec, "dados/projecoes_reconciliadas.rds")
message("Salvo: dados/projecoes_reconciliadas.rds  (",
        nrow(projecoes_rec), " linhas)")

# ==============================================================================
# Parte 6 — Reconciliar VAB por macrossetor
# ==============================================================================
# Dentro de cada geo × ano, escalonar macrossetores para que a soma
# bata com o VAB total reconciliado.

message("Reconciliando VAB por macrossetor...")

vab_total_rec <- projecoes_rec |>
  select(geo, ano, vab_total_rec = vab_nominal_total)

vab_macro_rec <- vab_macro |>
  group_by(geo, ano) |>
  mutate(soma_macro_bruta = sum(vab_nominal, na.rm = TRUE)) |>
  ungroup() |>
  left_join(vab_total_rec, by = c("geo", "ano")) |>
  mutate(
    fator_macro = if_else(soma_macro_bruta > 0,
                          vab_total_rec / soma_macro_bruta,
                          1),
    vab_nominal = vab_nominal * fator_macro
  ) |>
  select(-soma_macro_bruta, -vab_total_rec, -fator_macro)

saveRDS(vab_macro_rec, "dados/vab_macro_reconciliado.rds")
message("Salvo: dados/vab_macro_reconciliado.rds  (",
        nrow(vab_macro_rec), " linhas)")

# ==============================================================================
# Parte 6b — Reconciliar VAB por atividade individual
# ==============================================================================
# Escalonar VAB por atividade para que a soma (por geo × ano) iguale o VAB total
# reconciliado. Aplica o mesmo fator proporcional a ponto central e IC 95%.

if (file.exists("dados/vab_atividade_proj.rds")) {
  message("Reconciliando VAB por atividade...")

  vab_ativ_proj   <- readRDS("dados/vab_atividade_proj.rds")
  vab_total_rec_ref <- projecoes_rec |>
    select(geo, ano, vab_total_rec = vab_nominal_total)

  vab_ativ_rec <- vab_ativ_proj |>
    group_by(geo, ano) |>
    mutate(soma_ativ = sum(vab_nominal, na.rm = TRUE)) |>
    ungroup() |>
    left_join(vab_total_rec_ref, by = c("geo", "ano")) |>
    mutate(
      fator_ativ  = if_else(soma_ativ > 0, vab_total_rec / soma_ativ, 1),
      vab_nominal = vab_nominal * fator_ativ,
      vab_lo95    = vab_lo95    * fator_ativ,
      vab_hi95    = vab_hi95    * fator_ativ
    ) |>
    select(-soma_ativ, -vab_total_rec, -fator_ativ)

  saveRDS(vab_ativ_rec, "dados/vab_atividade_reconciliada.rds")
  message("Salvo: dados/vab_atividade_reconciliada.rds  (",
          nrow(vab_ativ_rec), " linhas)")

  # Verificação: soma das atividades = VAB total reconciliado
  check_ativ <- vab_ativ_rec |>
    group_by(geo, ano) |>
    summarise(soma_rec = sum(vab_nominal, na.rm = TRUE), .groups = "drop") |>
    left_join(vab_total_rec_ref, by = c("geo", "ano")) |>
    mutate(desvio_pct = abs(soma_rec - vab_total_rec) / vab_total_rec * 100)
  cat("Soma atividades = VAB total reconciliado:\n")
  cat("  desvio máximo =",
      round(max(check_ativ$desvio_pct, na.rm = TRUE), 8), "%\n")
} else {
  message("vab_atividade_proj.rds não encontrado — pulando reconciliação de atividades.")
}

# ==============================================================================
# Parte 7 — Verificações de consistência
# ==============================================================================

message("\n=== Verificações de consistência ===")

## 7a. Identidade PIB = VAB + Impostos ---------------------------------------
check_id <- projecoes_rec |>
  mutate(
    pib_recalc = vab_nominal_total + impostos_nominal,
    desvio_pct = abs(pib_nominal - pib_recalc) / pib_nominal * 100
  )

cat("Identidade PIB = VAB + Impostos:\n")
cat("  desvio máximo =", round(max(check_id$desvio_pct, na.rm = TRUE), 8), "%\n")

## 7b. Soma dos estados = região reconciliada --------------------------------
soma_uf_por_reg <- ufs_rec |>
  group_by(regiao, ano) |>
  summarise(soma_ufs_rec = sum(pib_nominal_rec, na.rm = TRUE), .groups = "drop")

check_reg <- regs_rec |>
  select(regiao = geo, ano, pib_reg_rec = pib_nominal_rec) |>
  left_join(soma_uf_por_reg, by = c("regiao", "ano")) |>
  mutate(desvio_pct = abs(soma_ufs_rec - pib_reg_rec) / pib_reg_rec * 100)

cat("Soma estados = região:\n")
cat("  desvio máximo =", round(max(check_reg$desvio_pct, na.rm = TRUE), 8), "%\n")
if (any(check_reg$desvio_pct > 0.001, na.rm = TRUE)) {
  cat("  ATENÇÃO: desvios > 0,001% detectados:\n")
  print(filter(check_reg, desvio_pct > 0.001))
}

## 7c. Soma das regiões = Brasil reconciliado --------------------------------
soma_reg_por_br <- regs_rec |>
  group_by(ano) |>
  summarise(soma_regs_rec = sum(pib_nominal_rec, na.rm = TRUE), .groups = "drop")

check_br <- br_rec |>
  select(ano, pib_brasil_rec = pib_nominal_rec) |>
  left_join(soma_reg_por_br, by = "ano") |>
  mutate(desvio_pct = abs(soma_regs_rec - pib_brasil_rec) / pib_brasil_rec * 100)

cat("Soma regiões = Brasil:\n")
cat("  desvio máximo =", round(max(check_br$desvio_pct, na.rm = TRUE), 8), "%\n")
if (any(check_br$desvio_pct > 0.001, na.rm = TRUE)) {
  cat("  ATENÇÃO: desvios > 0,001% detectados:\n")
  print(filter(check_br, desvio_pct > 0.001))
}

## 7d. Distribuição dos fatores de ajuste ------------------------------------
cat("\nFatores de ajuste (desvio das projeções brutas):\n")
projecoes_rec |>
  group_by(geo_tipo) |>
  summarise(
    min  = round(min(fator_ajuste,  na.rm = TRUE), 4),
    med  = round(mean(fator_ajuste, na.rm = TRUE), 4),
    max  = round(max(fator_ajuste,  na.rm = TRUE), 4),
    .groups = "drop"
  ) |>
  print()

## 7e. Amostra: Brasil e Roraima --------------------------------------------
cat("\nPIB nominal reconciliado — Brasil e Roraima:\n")
projecoes_rec |>
  filter(geo %in% c("Brasil", "Roraima")) |>
  select(geo, ano, pib_nominal, tx_cresc_pib_real, deflator_pib, fator_ajuste) |>
  mutate(
    pib_nominal       = round(pib_nominal / 1e6, 3),   # trilhões
    tx_cresc_pib_real = round(tx_cresc_pib_real * 100, 2),
    deflator_pib      = round(deflator_pib * 100, 2),
    fator_ajuste      = round(fator_ajuste, 4)
  ) |>
  rename(`PIB (tri R$)` = pib_nominal,
         `Cresc real (%)` = tx_cresc_pib_real,
         `Deflator (%)`   = deflator_pib,
         `Fator adj.`     = fator_ajuste) |>
  print(n = 20)

message("\n04_reconciliacao.R concluído.")
