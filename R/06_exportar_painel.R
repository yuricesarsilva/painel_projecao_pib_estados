source("R/config.R", local = FALSE)

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
# Saídas públicas em painel/data/:
#   serie_principal.csv  — histórico + projetado para 5 variáveis agregadas,
#                          limitado ao horizonte público do painel
#   vab_macrossetor.csv  — histórico + projetado por macrossetor, limitado ao
#                          horizonte público do painel
#   vab_atividade.csv    — histórico + projetado por atividade, limitado ao
#                          horizonte público do painel
#
# Saídas técnicas adicionais:
#   output/tabelas/projecoes_painel_h3.xlsx
#     — mesmas estruturas do painel, mas limitadas ao horizonte público
#   output/tabelas/projecoes_painel_h8.xlsx
#     — mesmas estruturas com o horizonte técnico completo (2024–2031)
#
# Estrutura comum (formato longo):
#   geo, geo_tipo, regiao, ano, <variavel(is)>, lo95, hi95, tipo, horizonte
#   tipo = "Histórico" (2002–2023) ou "Projetado" (2024–2031)
#   horizonte = "Histórico" | "Operacional" | "Exploratório"
#   lo95/hi95 = NA no período histórico
# ==============================================================================

dir.create("painel/data", recursive = TRUE, showWarnings = FALSE)
dir.create("output/tabelas", recursive = TRUE, showWarnings = FALSE)

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

# geo_meta: referência de geo_tipo e regiao para o join com séries históricas
# Usa esp porque cobre todos os anos históricos e todos os 33 geos
geo_meta <- esp |>
  filter(variavel == "pib_nominal", atividade == "total", ano == 2023) |>
  select(geo, geo_tipo, regiao)

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

# Séries históricas com geo_tipo e regiao incluídos diretamente
pib_nom_hist <- esp |>
  filter(variavel == "pib_nominal", atividade == "total") |>
  select(geo, geo_tipo, regiao, ano, pib_nominal = valor)

pib_vol_hist <- esp |>
  filter(variavel == "pib_vol_encadeado", atividade == "total") |>
  select(geo, geo_tipo, regiao, ano, vol_enc = valor)

vab_nom_hist <- esp |>
  filter(variavel == "vab_nominal", atividade == "total") |>
  select(geo, geo_tipo, regiao, ano, vab_nominal = valor)

imp_nom_hist <- esp |>
  filter(variavel == "impostos_nominal", atividade == "total") |>
  select(geo, geo_tipo, regiao, ano, impostos_nominal = valor)

# Referências base 2002 para índices acumulados
ref_2002 <- pib_vol_hist |>
  filter(ano == ANO_HIST_INI) |>
  select(geo, vol_enc_2002 = vol_enc)

ref_2002_nom <- pib_nom_hist |>
  filter(ano == ANO_HIST_INI) |>
  select(geo, pib_nom_2002 = pib_nominal)

# Histórico: índice de volume real e deflator acumulado (base 100 = 2002)
hist_indices <- pib_vol_hist |>
  left_join(pib_nom_hist |> select(geo, ano, pib_nominal), by = c("geo", "ano")) |>
  left_join(ref_2002,     by = "geo") |>
  left_join(ref_2002_nom, by = "geo") |>
  filter(ano >= ANO_HIST_INI) |>
  mutate(
    idx_vol_pib    = round(vol_enc / vol_enc_2002 * 100, 2),
    idx_deflator   = round((pib_nominal / pib_nom_2002) / (vol_enc / vol_enc_2002) * 100, 2)
  ) |>
  select(geo, geo_tipo, regiao, ano, idx_vol_pib, idx_deflator)

pib_2023_ref <- pib_nom_hist |>
  filter(ano == ANO_HIST_FIM) |>
  select(geo, pib_lag_base = pib_nominal)

# Valores de base em 2023 para continuação dos índices acumulados
base_idx_2023 <- hist_indices |>
  filter(ano == ANO_HIST_FIM) |>
  select(geo, idx_vol_2023 = idx_vol_pib, idx_defl_2023 = idx_deflator)

# Índices acumulados projetados com IC (base 100 = 2002, continuados de 2023)
proj_indices_ci <- proj_rec |>
  select(geo, ano, pib_nominal, tx_cresc_pib_real, deflator_pib) |>
  left_join(cresc_ci, by = c("geo", "ano")) |>
  left_join(pib_ci,   by = c("geo", "ano")) |>
  left_join(base_idx_2023, by = "geo") |>
  left_join(ref_2002_nom,  by = "geo") |>
  arrange(geo, ano) |>
  group_by(geo) |>
  mutate(
    # Índice de volume real acumulado (base 100 = 2002)
    idx_vol    = idx_vol_2023 * cumprod(1 + tx_cresc_pib_real),
    idx_vol_lo = idx_vol_2023 * cumprod(1 + coalesce(cresc_lo95, tx_cresc_pib_real)),
    idx_vol_hi = idx_vol_2023 * cumprod(1 + coalesce(cresc_hi95, tx_cresc_pib_real)),
    # Índice deflator acumulado (base 100 = 2002):
    # deflator_t = PIB_nominal_t / (PIB_nom_2002 * idx_vol_t / 100)
    idx_defl    = round((pib_nominal    / pib_nom_2002) / (idx_vol    / 100) * 100, 2),
    idx_defl_lo = round((coalesce(pib_lo95, pib_nominal) / pib_nom_2002) / (idx_vol_hi / 100) * 100, 2),
    idx_defl_hi = round((coalesce(pib_hi95, pib_nominal) / pib_nom_2002) / (idx_vol_lo / 100) * 100, 2)
  ) |>
  ungroup() |>
  mutate(across(c(idx_vol, idx_vol_lo, idx_vol_hi, idx_defl), \(x) round(x, 2))) |>
  select(geo, ano, idx_vol, idx_vol_lo, idx_vol_hi, idx_defl, idx_defl_lo, idx_defl_hi)

# ==============================================================================
# 1. serie_principal.csv
# Formato longo: geo, geo_tipo, regiao, ano, variavel, valor, lo95, hi95, tipo
# Variáveis: pib_nominal, vab_nominal_total, impostos_nominal,
#            idx_vol_pib (índice volume real, base 100 = 2002),
#            idx_deflator (índice deflator acumulado, base 100 = 2002)
# ==============================================================================

message("Montando serie_principal.csv...")

classificar_horizonte <- function(ano, tipo) {
  case_when(
    tipo == "Histórico" ~ "Histórico",
    ano <= ANO_OPERACIONAL_FIM ~ "Operacional",
    TRUE ~ "Exploratório"
  )
}

filtrar_horizonte_painel <- function(df) {
  df |>
    filter(tipo == "Histórico" | ano <= ANO_PAINEL_PROJ_FIM)
}

# Histórico: 5 variáveis em formato longo (geo_tipo/regiao já nas séries)
hist_principal <- bind_rows(
  pib_nom_hist |>
    filter(ano >= ANO_HIST_INI) |>
    transmute(geo, geo_tipo, regiao, ano,
              variavel = "pib_nominal",
              valor = pib_nominal,
              lo95 = NA_real_, hi95 = NA_real_,
              tipo = "Histórico",
              horizonte = classificar_horizonte(ano, "Histórico")),
  vab_nom_hist |>
    filter(ano >= ANO_HIST_INI) |>
    transmute(geo, geo_tipo, regiao, ano,
              variavel = "vab_nominal_total",
              valor = vab_nominal,
              lo95 = NA_real_, hi95 = NA_real_,
              tipo = "Histórico",
              horizonte = classificar_horizonte(ano, "Histórico")),
  imp_nom_hist |>
    filter(ano >= ANO_HIST_INI) |>
    transmute(geo, geo_tipo, regiao, ano,
              variavel = "impostos_nominal",
              valor = impostos_nominal,
              lo95 = NA_real_, hi95 = NA_real_,
              tipo = "Histórico",
              horizonte = classificar_horizonte(ano, "Histórico")),
  hist_indices |>
    transmute(geo, geo_tipo, regiao, ano,
              variavel = "idx_vol_pib",
              valor = idx_vol_pib,
              lo95 = NA_real_, hi95 = NA_real_,
              tipo = "Histórico",
              horizonte = classificar_horizonte(ano, "Histórico")),
  hist_indices |>
    transmute(geo, geo_tipo, regiao, ano,
              variavel = "idx_deflator",
              valor = idx_deflator,
              lo95 = NA_real_, hi95 = NA_real_,
              tipo = "Histórico",
              horizonte = classificar_horizonte(ano, "Histórico"))
)

# Projetado: 5 variáveis em formato longo
proj_principal <- bind_rows(
  proj_rec |>
    left_join(pib_ci, by = c("geo", "ano")) |>

    transmute(geo, geo_tipo, regiao, ano,
              variavel = "pib_nominal",
              valor = pib_nominal,
              lo95 = pib_lo95, hi95 = pib_hi95,
              tipo = "Projetado",
              horizonte = classificar_horizonte(ano, "Projetado")),
  proj_rec |>
    left_join(vab_total_ci, by = c("geo", "ano")) |>

    transmute(geo, geo_tipo, regiao, ano,
              variavel = "vab_nominal_total",
              valor = vab_nominal_total,
              lo95 = vab_lo95, hi95 = vab_hi95,
              tipo = "Projetado",
              horizonte = classificar_horizonte(ano, "Projetado")),
  proj_rec |>
    left_join(imp_ci, by = c("geo", "ano")) |>

    transmute(geo, geo_tipo, regiao, ano,
              variavel = "impostos_nominal",
              valor = impostos_nominal,
              lo95 = imp_lo95, hi95 = imp_hi95,
              tipo = "Projetado",
              horizonte = classificar_horizonte(ano, "Projetado")),
  proj_rec |>
    left_join(proj_indices_ci, by = c("geo", "ano")) |>
    transmute(geo, geo_tipo, regiao, ano,
              variavel = "idx_vol_pib",
              valor = idx_vol,
              lo95 = idx_vol_lo, hi95 = idx_vol_hi,
              tipo = "Projetado",
              horizonte = classificar_horizonte(ano, "Projetado")),
  proj_rec |>
    left_join(proj_indices_ci, by = c("geo", "ano")) |>
    transmute(geo, geo_tipo, regiao, ano,
              variavel = "idx_deflator",
              valor = idx_defl,
              lo95 = idx_defl_lo, hi95 = idx_defl_hi,
              tipo = "Projetado",
              horizonte = classificar_horizonte(ano, "Projetado"))
)

serie_principal <- bind_rows(hist_principal, proj_principal) |>
  arrange(geo, variavel, ano)

serie_principal_painel <- filtrar_horizonte_painel(serie_principal)

write.csv(serie_principal_painel, "painel/data/serie_principal.csv",
          row.names = FALSE, na = "")
message("  serie_principal.csv: ", nrow(serie_principal_painel), " linhas")

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
  transmute(geo, geo_tipo, regiao, macrossetor, ano,
            vab_nominal = val_corrente,
            vab_lo95 = NA_real_, vab_hi95 = NA_real_,
            tipo = "Histórico",
            horizonte = classificar_horizonte(ano, "Histórico"))

proj_mac <- vab_mac_ci |>
  left_join(geo_meta, by = "geo") |>
  transmute(geo, geo_tipo, regiao, macrossetor, ano,
            vab_nominal, vab_lo95, vab_hi95,
            tipo = "Projetado",
            horizonte = classificar_horizonte(ano, "Projetado"))

vab_macrossetor_out <- bind_rows(hist_mac, proj_mac) |>
  arrange(geo, macrossetor, ano)

vab_macrossetor_painel <- filtrar_horizonte_painel(vab_macrossetor_out)

write.csv(vab_macrossetor_painel, "painel/data/vab_macrossetor.csv",
          row.names = FALSE, na = "")
message("  vab_macrossetor.csv: ", nrow(vab_macrossetor_painel), " linhas")

# ==============================================================================
# 3. vab_atividade.csv
# Formato: geo, geo_tipo, regiao, atividade, macrossetor, ano, vab_nominal,
#          vab_lo95, vab_hi95, tipo
# ==============================================================================

if (!is.null(vab_ativ_hist) && !is.null(vab_ativ_rec)) {
  message("Montando vab_atividade.csv...")

  hist_ativ <- vab_ativ_hist |>
    left_join(ATIV_MACRO_MAP, by = "atividade") |>
    transmute(geo, geo_tipo, regiao, atividade, macrossetor, ano,
              vab_nominal = val_corrente,
              vab_lo95 = NA_real_, vab_hi95 = NA_real_,
              tipo = "Histórico",
              horizonte = classificar_horizonte(ano, "Histórico"))

  proj_ativ <- vab_ativ_rec |>
    left_join(geo_meta |> select(geo, geo_tipo, regiao), by = "geo") |>
    transmute(geo, geo_tipo, regiao, atividade, macrossetor, ano,
              vab_nominal, vab_lo95, vab_hi95,
              tipo = "Projetado",
              horizonte = classificar_horizonte(ano, "Projetado"))

  vab_atividade_out <- bind_rows(hist_ativ, proj_ativ) |>
    arrange(geo, atividade, ano)

  vab_atividade_painel <- filtrar_horizonte_painel(vab_atividade_out)

  write.csv(vab_atividade_painel, "painel/data/vab_atividade.csv",
            row.names = FALSE, na = "")
  message("  vab_atividade.csv: ", nrow(vab_atividade_painel), " linhas")
} else {
  message("vab_atividade_hist.rds ou vab_atividade_reconciliada.rds não encontrados — pulando.")
}

message("Salvando saídas técnicas adicionais (h=3 e h=8)...")

serie_principal_h3 <- serie_principal_painel |>
  filter(tipo == "Projetado")

vab_macrossetor_h3 <- vab_macrossetor_painel |>
  filter(tipo == "Projetado")

wb_h3 <- openxlsx::createWorkbook()

openxlsx::addWorksheet(wb_h3, "serie_principal_h3")
openxlsx::writeData(wb_h3, "serie_principal_h3", serie_principal_h3)

openxlsx::addWorksheet(wb_h3, "vab_macrossetor_h3")
openxlsx::writeData(wb_h3, "vab_macrossetor_h3", vab_macrossetor_h3)

if (exists("vab_atividade_painel")) {
  vab_atividade_h3 <- vab_atividade_painel |>
    filter(tipo == "Projetado")

  openxlsx::addWorksheet(wb_h3, "vab_atividade_h3")
  openxlsx::writeData(wb_h3, "vab_atividade_h3", vab_atividade_h3)
}

openxlsx::saveWorkbook(
  wb_h3,
  "output/tabelas/projecoes_painel_h3.xlsx",
  overwrite = TRUE
)

message("  projecoes_painel_h3.xlsx: horizonte público 2024–2026 preservado")

wb_h8 <- openxlsx::createWorkbook()

serie_principal_h8 <- serie_principal |>
  filter(tipo == "Projetado")

vab_macrossetor_h8 <- vab_macrossetor_out |>
  filter(tipo == "Projetado")

openxlsx::addWorksheet(wb_h8, "serie_principal_h8")
openxlsx::writeData(wb_h8, "serie_principal_h8", serie_principal_h8)

openxlsx::addWorksheet(wb_h8, "vab_macrossetor_h8")
openxlsx::writeData(wb_h8, "vab_macrossetor_h8", vab_macrossetor_h8)

if (exists("vab_atividade_out")) {
  vab_atividade_h8 <- vab_atividade_out |>
    filter(tipo == "Projetado")

  openxlsx::addWorksheet(wb_h8, "vab_atividade_h8")
  openxlsx::writeData(wb_h8, "vab_atividade_h8", vab_atividade_h8)
}

openxlsx::saveWorkbook(
  wb_h8,
  "output/tabelas/projecoes_painel_h8.xlsx",
  overwrite = TRUE
)

message("  projecoes_painel_h8.xlsx: horizonte técnico 2024–2031 preservado")

message("\n06_exportar_painel.R concluído. CSVs em painel/data/")
