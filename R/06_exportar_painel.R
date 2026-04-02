library(tidyverse)

# ==============================================================================
# 06_exportar_painel.R
#
# Exporta os dados do pipeline para CSV em painel/data/, tornando-os
# acessíveis ao painel Quarto + shinylive publicado no GitHub Pages.
# (O shinylive roda no browser via WebAssembly — sem acesso ao disco,
#  portanto os dados precisam estar disponíveis via HTTP como arquivos estáticos.)
#
# Deve ser executado a partir da raiz do projeto após rodar o pipeline
# completo (01 a 04).
#
# Saídas em painel/data/:
#   serie_principal.csv  — histórico + projetado para 5 variáveis agregadas,
#                          com IC 95% no período projetado
#   vab_macrossetor.csv  — histórico + projetado por macrossetor, com IC 95%
#   vab_atividade.csv    — histórico + projetado por atividade, com IC 95%
#
# Estrutura comum (formato longo):
#   geo, geo_tipo, regiao, ano, <variavel(is)>, lo95, hi95, tipo
#   tipo = "Histórico" (2002–2023) ou "Projetado" (2024–2031)
#   lo95/hi95 = NA no período histórico
# ==============================================================================

ANO_HIST_INI <- 2002L
ANO_HIST_FIM <- 2023L

dir.create("painel/data", recursive = TRUE, showWarnings = FALSE)

message("Carregando dados...")
esp         <- readRDS("dados/especiais.rds")
proj_rec    <- readRDS("dados/projecoes_reconciliadas.rds")
vab_mac     <- readRDS("dados/vab_macro_reconciliado.rds")
proj_brutas <- readRDS("dados/projecoes_brutas.rds")
vab_hist    <- readRDS("dados/vab_macro_hist.rds")

vab_ativ_hist <- if (file.exists("dados/vab_atividade_hist.rds"))
  readRDS("dados/vab_atividade_hist.rds") else NULL
vab_ativ_rec  <- if (file.exists("dados/vab_atividade_reconciliada.rds"))
  readRDS("dados/vab_atividade_reconciliada.rds") else NULL

geo_meta <- esp |> distinct(geo, geo_tipo, regiao)

# ==============================================================================
# Calcular IC 95% (mesma lógica de 05_output.R Parte 2b)
# ==============================================================================

# CI impostos
imp_ci <- proj_brutas |>
  filter(variavel == "log_impostos") |>
  transmute(
    geo, ano,
    imp_lo95 = exp(coalesce(lo95, proj)),
    imp_hi95 = exp(coalesce(hi95, proj))
  ) |>
  left_join(proj_rec |> select(geo, ano, fator_ajuste), by = c("geo", "ano")) |>
  mutate(
    imp_lo95 = imp_lo95 * coalesce(fator_ajuste, 1),
    imp_hi95 = imp_hi95 * coalesce(fator_ajuste, 1)
  ) |>
  select(-fator_ajuste)

# CI VAB macrossetor (propaga CI dos índices)
has_ci <- all(c("idx_vol_lo95", "idx_vol_hi95", "idx_prc_lo95", "idx_prc_hi95",
                "vab_2023", "fator_acum", "idx_volume", "idx_preco") %in% names(vab_mac))

if (has_ci) {
  vab_mac_ci <- vab_mac |>
    arrange(geo, macrossetor, ano) |>
    group_by(geo, macrossetor) |>
    mutate(
      flo  = cumprod(coalesce(idx_vol_lo95, idx_volume) *
                     coalesce(idx_prc_lo95, idx_preco)),
      fhi  = cumprod(coalesce(idx_vol_hi95, idx_volume) *
                     coalesce(idx_prc_hi95, idx_preco)),
      fadj = if_else(fator_acum > 0 & !is.na(fator_acum),
                     vab_nominal / (vab_2023 * fator_acum), 1),
      vab_lo95 = vab_2023 * flo * fadj,
      vab_hi95 = vab_2023 * fhi * fadj
    ) |>
    ungroup() |>
    select(geo, macrossetor, ano, vab_nominal, vab_lo95, vab_hi95)

  vab_total_ci <- vab_mac_ci |>
    group_by(geo, ano) |>
    summarise(vab_lo95 = sum(vab_lo95, na.rm = TRUE),
              vab_hi95 = sum(vab_hi95, na.rm = TRUE),
              .groups = "drop")

  pib_ci <- vab_total_ci |>
    left_join(imp_ci, by = c("geo", "ano")) |>
    transmute(geo, ano,
              pib_lo95 = vab_lo95 + imp_lo95,
              pib_hi95 = vab_hi95 + imp_hi95)

  pesos_2023 <- vab_mac |>
    distinct(geo, macrossetor, vab_2023) |>
    group_by(geo) |>
    mutate(peso = vab_2023 / sum(vab_2023, na.rm = TRUE)) |>
    ungroup()

  cresc_ci <- vab_mac |>
    left_join(pesos_2023 |> select(geo, macrossetor, peso),
              by = c("geo", "macrossetor")) |>
    mutate(
      idx_lo = coalesce(idx_vol_lo95, idx_volume),
      idx_hi = coalesce(idx_vol_hi95, idx_volume)
    ) |>
    group_by(geo, ano) |>
    summarise(
      cresc_lo95 = sum((idx_lo - 1) * peso, na.rm = TRUE),
      cresc_hi95 = sum((idx_hi - 1) * peso, na.rm = TRUE),
      .groups = "drop"
    )
} else {
  message("AVISO: colunas CI ausentes em vab_macro_reconciliado — IC será NA.")
  vab_mac_ci  <- vab_mac |>
    select(geo, macrossetor, ano, vab_nominal) |>
    mutate(vab_lo95 = NA_real_, vab_hi95 = NA_real_)
  vab_total_ci <- tibble(geo = character(), ano = integer(),
                         vab_lo95 = double(), vab_hi95 = double())
  pib_ci       <- tibble(geo = character(), ano = integer(),
                         pib_lo95 = double(), pib_hi95 = double())
  cresc_ci     <- tibble(geo = character(), ano = integer(),
                         cresc_lo95 = double(), cresc_hi95 = double())
}

# Deflator histórico
pib_nom_hist <- esp |>
  filter(variavel == "pib_nominal", atividade == "total") |>
  select(geo, ano, pib_nominal = valor)

pib_vol_hist <- esp |>
  filter(variavel == "pib_vol_encadeado", atividade == "total") |>
  select(geo, ano, vol_enc = valor)

hist_cresc <- pib_vol_hist |>
  arrange(geo, ano) |>
  group_by(geo) |>
  mutate(tx_cresc_pib_real = vol_enc / lag(vol_enc) - 1) |>
  ungroup() |>
  filter(!is.na(tx_cresc_pib_real)) |>
  select(geo, ano, tx_cresc_pib_real)

hist_deflator <- pib_nom_hist |>
  left_join(pib_vol_hist, by = c("geo", "ano")) |>
  arrange(geo, ano) |>
  group_by(geo) |>
  mutate(
    g_nom = pib_nominal / lag(pib_nominal) - 1,
    g_vol = vol_enc     / lag(vol_enc)     - 1,
    deflator_pib = (1 + g_nom) / (1 + g_vol) - 1
  ) |>
  ungroup() |>
  filter(!is.na(deflator_pib)) |>
  select(geo, ano, deflator_pib)

pib_2023_ref <- pib_nom_hist |>
  filter(ano == ANO_HIST_FIM) |>
  select(geo, pib_lag_base = pib_nominal)

proj_deflator <- proj_rec |>
  select(geo, ano, pib_nominal, tx_cresc_pib_real) |>
  arrange(geo, ano) |>
  group_by(geo) |>
  mutate(pib_lag_proj = lag(pib_nominal)) |>
  ungroup() |>
  left_join(pib_2023_ref, by = "geo") |>
  mutate(
    pib_lag      = coalesce(pib_lag_proj, pib_lag_base),
    g_nom        = pib_nominal / pib_lag - 1,
    deflator_pib = (1 + g_nom) / (1 + tx_cresc_pib_real) - 1
  ) |>
  select(geo, ano, deflator_pib)

# ==============================================================================
# 1. serie_principal.csv
# Formato longo: geo, geo_tipo, regiao, ano, variavel, valor, lo95, hi95, tipo
# Variáveis: pib_nominal, vab_nominal_total, impostos_nominal,
#            tx_cresc_pib_real (%), deflator_pib (%)
# ==============================================================================

message("Montando serie_principal.csv...")

vab_nom_hist <- esp |>
  filter(variavel == "vab_nominal", atividade == "total") |>
  select(geo, ano, vab_nominal = valor)

imp_nom_hist <- esp |>
  filter(variavel == "impostos_nominal", atividade == "total") |>
  select(geo, ano, impostos_nominal = valor)

# Histórico: 5 variáveis em formato longo
hist_principal <- bind_rows(
  pib_nom_hist |>
    filter(ano >= ANO_HIST_INI) |>
    left_join(geo_meta, by = "geo") |>
    transmute(geo, geo_tipo, regiao, ano,
              variavel = "pib_nominal",
              valor = pib_nominal,
              lo95 = NA_real_, hi95 = NA_real_,
              tipo = "Histórico"),
  vab_nom_hist |>
    filter(ano >= ANO_HIST_INI) |>
    left_join(geo_meta, by = "geo") |>
    transmute(geo, geo_tipo, regiao, ano,
              variavel = "vab_nominal_total",
              valor = vab_nominal,
              lo95 = NA_real_, hi95 = NA_real_,
              tipo = "Histórico"),
  imp_nom_hist |>
    filter(ano >= ANO_HIST_INI) |>
    left_join(geo_meta, by = "geo") |>
    transmute(geo, geo_tipo, regiao, ano,
              variavel = "impostos_nominal",
              valor = impostos_nominal,
              lo95 = NA_real_, hi95 = NA_real_,
              tipo = "Histórico"),
  hist_cresc |>
    filter(ano >= ANO_HIST_INI + 1L) |>
    left_join(geo_meta, by = "geo") |>
    transmute(geo, geo_tipo, regiao, ano,
              variavel = "cresc_real_pib",
              valor = round(tx_cresc_pib_real * 100, 3),
              lo95 = NA_real_, hi95 = NA_real_,
              tipo = "Histórico"),
  hist_deflator |>
    filter(ano >= ANO_HIST_INI + 1L) |>
    left_join(geo_meta, by = "geo") |>
    transmute(geo, geo_tipo, regiao, ano,
              variavel = "deflator_pib",
              valor = round(deflator_pib * 100, 3),
              lo95 = NA_real_, hi95 = NA_real_,
              tipo = "Histórico")
)

# Projetado: 5 variáveis em formato longo
proj_principal <- bind_rows(
  proj_rec |>
    left_join(pib_ci, by = c("geo", "ano")) |>
    left_join(geo_meta, by = "geo") |>
    transmute(geo, geo_tipo, regiao, ano,
              variavel = "pib_nominal",
              valor = pib_nominal,
              lo95 = pib_lo95, hi95 = pib_hi95,
              tipo = "Projetado"),
  proj_rec |>
    left_join(vab_total_ci, by = c("geo", "ano")) |>
    left_join(geo_meta, by = "geo") |>
    transmute(geo, geo_tipo, regiao, ano,
              variavel = "vab_nominal_total",
              valor = vab_nominal_total,
              lo95 = vab_lo95, hi95 = vab_hi95,
              tipo = "Projetado"),
  proj_rec |>
    left_join(imp_ci, by = c("geo", "ano")) |>
    left_join(geo_meta, by = "geo") |>
    transmute(geo, geo_tipo, regiao, ano,
              variavel = "impostos_nominal",
              valor = impostos_nominal,
              lo95 = imp_lo95, hi95 = imp_hi95,
              tipo = "Projetado"),
  proj_rec |>
    left_join(cresc_ci, by = c("geo", "ano")) |>
    left_join(geo_meta, by = "geo") |>
    transmute(geo, geo_tipo, regiao, ano,
              variavel = "cresc_real_pib",
              valor = round(tx_cresc_pib_real * 100, 3),
              lo95 = round(cresc_lo95 * 100, 3),
              hi95 = round(cresc_hi95 * 100, 3),
              tipo = "Projetado"),
  proj_rec |>
    left_join(proj_deflator, by = c("geo", "ano")) |>
    left_join(geo_meta, by = "geo") |>
    transmute(geo, geo_tipo, regiao, ano,
              variavel = "deflator_pib",
              valor = round(deflator_pib * 100, 3),
              lo95 = NA_real_, hi95 = NA_real_,
              tipo = "Projetado")
)

serie_principal <- bind_rows(hist_principal, proj_principal) |>
  arrange(geo, variavel, ano)

write.csv(serie_principal, "painel/data/serie_principal.csv",
          row.names = FALSE, na = "")
message("  serie_principal.csv: ", nrow(serie_principal), " linhas")

# ==============================================================================
# 2. vab_macrossetor.csv
# Formato: geo, geo_tipo, regiao, macrossetor, ano, vab_nominal,
#          vab_lo95, vab_hi95, tipo
# ==============================================================================

message("Montando vab_macrossetor.csv...")

ATIV_MACRO_MAP <- tibble(
  atividade   = c("agropecuaria",
                  "ind_extrativa", "ind_transformacao",
                  "eletricidade_gas_agua", "construcao",
                  "comercio_veiculos", "transporte_armazenagem",
                  "informacao_comunicacao", "financeiro_seguros",
                  "imobiliaria", "adm_publica", "outros_servicos"),
  macrossetor = c("agropecuaria",
                  "industria", "industria", "industria", "industria",
                  "servicos", "servicos", "servicos", "servicos", "servicos",
                  "adm_publica", "servicos")
)

hist_mac <- vab_hist |>
  left_join(geo_meta, by = "geo") |>
  transmute(geo, geo_tipo, regiao, macrossetor, ano,
            vab_nominal = val_corrente,
            vab_lo95 = NA_real_, vab_hi95 = NA_real_,
            tipo = "Histórico")

proj_mac <- vab_mac_ci |>
  left_join(geo_meta, by = "geo") |>
  transmute(geo, geo_tipo, regiao, macrossetor, ano,
            vab_nominal, vab_lo95, vab_hi95,
            tipo = "Projetado")

vab_macrossetor_out <- bind_rows(hist_mac, proj_mac) |>
  arrange(geo, macrossetor, ano)

write.csv(vab_macrossetor_out, "painel/data/vab_macrossetor.csv",
          row.names = FALSE, na = "")
message("  vab_macrossetor.csv: ", nrow(vab_macrossetor_out), " linhas")

# ==============================================================================
# 3. vab_atividade.csv
# Formato: geo, geo_tipo, regiao, atividade, macrossetor, ano, vab_nominal,
#          vab_lo95, vab_hi95, tipo
# ==============================================================================

if (!is.null(vab_ativ_hist) && !is.null(vab_ativ_rec)) {
  message("Montando vab_atividade.csv...")

  hist_ativ <- vab_ativ_hist |>
    left_join(geo_meta, by = "geo") |>
    left_join(ATIV_MACRO_MAP, by = "atividade") |>
    transmute(geo, geo_tipo, regiao, atividade, macrossetor, ano,
              vab_nominal = val_corrente,
              vab_lo95 = NA_real_, vab_hi95 = NA_real_,
              tipo = "Histórico")

  proj_ativ <- vab_ativ_rec |>
    left_join(geo_meta, by = "geo") |>
    transmute(geo, geo_tipo, regiao, atividade, macrossetor, ano,
              vab_nominal, vab_lo95, vab_hi95,
              tipo = "Projetado")

  vab_atividade_out <- bind_rows(hist_ativ, proj_ativ) |>
    arrange(geo, atividade, ano)

  write.csv(vab_atividade_out, "painel/data/vab_atividade.csv",
            row.names = FALSE, na = "")
  message("  vab_atividade.csv: ", nrow(vab_atividade_out), " linhas")
} else {
  message("vab_atividade_hist.rds ou vab_atividade_reconciliada.rds não encontrados — pulando.")
}

message("\n06_exportar_painel.R concluído. CSVs em painel/data/")