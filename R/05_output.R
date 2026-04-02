library(tidyverse)

if (!requireNamespace("openxlsx", quietly = TRUE))
  install.packages("openxlsx", repos = "https://cloud.r-project.org")
library(openxlsx)

if (!requireNamespace("RColorBrewer", quietly = TRUE))
  install.packages("RColorBrewer", repos = "https://cloud.r-project.org")
library(RColorBrewer)

# ==============================================================================
# 05_output.R
#
# Gera tabelas Excel e gráficos a partir das projeções reconciliadas.
# Cobre todos os 33 territórios, todas as séries, com IC 95%.
#
# Entradas:
#   dados/especiais.rds                  — histórico PIB/VAB/impostos/volume
#   dados/projecoes_reconciliadas.rds    — PIB, VAB, impostos, deflator, cresc.
#                                          real, fator_ajuste por geo × ano
#   dados/vab_macro_reconciliado.rds     — VAB por macrossetor reconciliado;
#                                          contém colunas CI dos índices
#                                          (idx_vol_lo95/hi95, idx_prc_lo95/hi95,
#                                          vab_2023, fator_acum) herdadas de
#                                          vab_macrossetor_proj.rds
#   dados/projecoes_brutas.rds           — séries brutas projetadas com IC;
#                                          usado para CI de log_impostos e
#                                          para os gráficos de séries brutas
#   dados/vab_macro_hist.rds             — série histórica VAB por macrossetor
#                                          (val_corrente, idx_volume, idx_preco)
#   dados/vab_atividade_hist.rds         — série histórica VAB por atividade
#   dados/vab_atividade_reconciliada.rds — VAB por atividade projetado + IC 95%
#                                          reconciliado (opcional)
#   dados/params_modelos.rds             — modelo selecionado, parâmetros,
#                                          MASE e RMSE por série (opcional)
#
# Intervalos de confiança (IC 95%) calculados para:
#   VAB macrossetor : propaga CI dos índices → aplica fator de reconciliação
#   VAB atividade   : herdado de vab_atividade_reconciliada (já com fator)
#   VAB total       : soma dos IC dos macrossetores
#   Impostos        : exp(lo95/hi95 de log_impostos) × fator_ajuste
#   PIB nominal     : vab_ci + impostos_ci
#   Crescimento real: média ponderada dos idx_vol_lo95/hi95 (pesos = VAB 2023)
#
# Saídas:
#   output/tabelas/projecoes_pib_estadual.xlsx
#     Abas: PIB_nominal | VAB_nominal | Impostos_nominais | Cresc_real_PIB |
#           Deflator_PIB | VAB_macrossetor | VAB_atividade |
#           Intervalos_Confianca | Selecao_Modelos
#     Linha separadora vermelha entre histórico (2002–2023) e projetado
#     (2024–2031) em todas as abas.
#   output/graficos/todas_geos/
#     pib_nominal.png, vab_nominal.png, impostos_nominal.png,
#     cresc_real_pib.png, deflator_pib.png,
#     vab_{macrossetor}.png  (4 plots, um por macrossetor),
#     vab_ativ_{atividade}.png  (12 plots, um por atividade)
#     Total: 21 plots — todos os 33 territórios facetados, ribbon IC 95%
#   output/graficos/por_geo/
#     {geo}.png — 33 plots, 1 por território, com 9+ painéis: PIB, VAB,
#     impostos, cresc. real, deflator, VAB por 4 macrossetores
#   output/graficos/por_geo_atividade/
#     {geo}.png — 33 stacked-area plots: VAB decomposto por 12 atividades,
#     histórico + projetado
#   output/graficos/series_brutas/
#     idx_volume_{macro}.png, idx_preco_{macro}.png  (8 plots),
#     log_impostos.png  (1 plot)
#     Total: 9 plots — séries modeladas diretamente com CI 95%
#   output/graficos/  (5 plots de resumo)
#     pib_nominal_brasil.png, cresc_real_regioes.png,
#     pib_nominal_roraima.png, fatores_ajuste.png,
#     participacao_pib_estados.png
# ==============================================================================

# ==============================================================================
# Parte 0 — Parâmetros e diretórios
# ==============================================================================

ANO_HIST_INI <- 2002L
ANO_HIST_FIM <- 2023L
ANO_PROJ_FIM <- 2031L

GEO_ORDER <- c(
  "Brasil",
  "Norte",        "Rondônia", "Acre", "Amazonas", "Roraima",
                  "Pará", "Amapá", "Tocantins",
  "Nordeste",     "Maranhão", "Piauí", "Ceará", "Rio Grande do Norte",
                  "Paraíba", "Pernambuco", "Alagoas", "Sergipe", "Bahia",
  "Sudeste",      "Minas Gerais", "Espírito Santo", "Rio de Janeiro", "São Paulo",
  "Sul",          "Paraná", "Santa Catarina", "Rio Grande do Sul",
  "Centro-Oeste", "Mato Grosso do Sul", "Mato Grosso", "Goiás", "Distrito Federal"
)

GEO_AGREGADO <- c("Brasil", "Norte", "Nordeste", "Sudeste", "Sul", "Centro-Oeste")

for (d in c("output/tabelas", "output/graficos",
            "output/graficos/todas_geos",
            "output/graficos/por_geo",
            "output/graficos/por_geo_atividade",
            "output/graficos/series_brutas")) {
  dir.create(d, showWarnings = FALSE, recursive = TRUE)
}

# Rótulos legíveis das 12 atividades individuais
ATIVIDADE_LABEL <- c(
  agropecuaria           = "Agropecuária",
  ind_extrativa          = "Ind. Extrativas",
  ind_transformacao      = "Ind. de Transformação",
  eletricidade_gas_agua  = "Eletricidade/Gás/Água",
  construcao             = "Construção",
  comercio_veiculos      = "Comércio e Veículos",
  transporte_armazenagem = "Transporte e Armazenagem",
  informacao_comunicacao = "Informação e Comunicação",
  financeiro_seguros     = "Financeiro e Seguros",
  imobiliaria            = "Atividades Imobiliárias",
  adm_publica            = "Adm. Pública",
  outros_servicos        = "Outros Serviços"
)

ATIVIDADES <- names(ATIVIDADE_LABEL)

# ==============================================================================
# Parte 1 — Carregar dados
# ==============================================================================

message("Carregando dados...")
esp         <- readRDS("dados/especiais.rds")
proj_rec    <- readRDS("dados/projecoes_reconciliadas.rds")
vab_mac     <- readRDS("dados/vab_macro_reconciliado.rds")
proj_brutas <- readRDS("dados/projecoes_brutas.rds")
params_mod   <- if (file.exists("dados/params_modelos.rds"))
  readRDS("dados/params_modelos.rds") else NULL
vab_hist     <- if (file.exists("dados/vab_macro_hist.rds"))
  readRDS("dados/vab_macro_hist.rds") else NULL
vab_ativ_hist <- if (file.exists("dados/vab_atividade_hist.rds"))
  readRDS("dados/vab_atividade_hist.rds") else NULL
vab_ativ_rec  <- if (file.exists("dados/vab_atividade_reconciliada.rds"))
  readRDS("dados/vab_atividade_reconciliada.rds") else NULL

geo_ref <- esp |> distinct(geo, geo_tipo, regiao)

# Verificar disponibilidade de colunas de CI em vab_mac
has_ci <- all(c("idx_vol_lo95", "idx_vol_hi95", "idx_prc_lo95", "idx_prc_hi95",
                "vab_2023", "fator_acum", "idx_volume", "idx_preco") %in% names(vab_mac))
if (!has_ci) {
  message("AVISO: colunas de CI ausentes em vab_macro_reconciliado.rds. ",
          "Regere 03_projecao.R e 04_reconciliacao.R para gerar CI completo.")
}

# ==============================================================================
# Parte 2 — Séries históricas derivadas
# ==============================================================================

pib_nom_hist <- esp |>
  filter(variavel == "pib_nominal", atividade == "total") |>
  select(geo, ano, pib_nominal = valor)

pib_vol_hist <- esp |>
  filter(variavel == "pib_vol_encadeado", atividade == "total") |>
  select(geo, ano, vol_enc = valor)

vab_nom_hist <- esp |>
  filter(variavel == "vab_nominal", atividade == "total") |>
  select(geo, ano, vab_nominal = valor)

imp_nom_hist <- esp |>
  filter(variavel == "impostos_nominal", atividade == "total") |>
  select(geo, ano, impostos_nominal = valor)

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
# Parte 2b — Intervalos de confiança (IC 95%) para o período projetado
# ==============================================================================

message("Calculando intervalos de confiança...")

# --- CI impostos: exp(CI do log_impostos) × fator_ajuste de reconciliação
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

# --- CI VAB por macrossetor: propaga CI dos índices; aplica fator de reconciliação
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

  # CI crescimento real: média ponderada dos CIs dos índices de volume (peso = VAB 2023)
  pesos_2023 <- vab_mac |>
    distinct(geo, macrossetor, vab_2023) |>
    group_by(geo) |>
    mutate(peso = vab_2023 / sum(vab_2023, na.rm = TRUE)) |>
    ungroup()

  cresc_ci <- vab_mac |>
    left_join(pesos_2023 |> select(geo, macrossetor, peso), by = c("geo", "macrossetor")) |>
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
  vab_mac_ci   <- vab_mac |> select(geo, macrossetor, ano, vab_nominal) |>
    mutate(vab_lo95 = NA_real_, vab_hi95 = NA_real_)
  vab_total_ci <- tibble(geo = character(), ano = integer(),
                         vab_lo95 = double(), vab_hi95 = double())
  pib_ci       <- tibble(geo = character(), ano = integer(),
                         pib_lo95 = double(), pib_hi95 = double())
  cresc_ci     <- tibble(geo = character(), ano = integer(),
                         cresc_lo95 = double(), cresc_hi95 = double())
}

# ==============================================================================
# Parte 3 — Montar séries combinadas e pivotar para wide (ano × geo)
# ==============================================================================

to_wide <- function(df, value_col) {
  df |>
    filter(geo %in% GEO_ORDER) |>
    mutate(geo = factor(geo, levels = GEO_ORDER)) |>
    select(ano, geo, valor = all_of(value_col)) |>
    pivot_wider(names_from = geo, values_from = valor) |>
    arrange(ano)
}

pib_wide <- bind_rows(
  pib_nom_hist |> filter(ano >= ANO_HIST_INI),
  proj_rec     |> select(geo, ano, pib_nominal)
) |> to_wide("pib_nominal")

vab_wide <- bind_rows(
  vab_nom_hist |> filter(ano >= ANO_HIST_INI),
  proj_rec     |> select(geo, ano, vab_nominal = vab_nominal_total)
) |> to_wide("vab_nominal")

imp_wide <- bind_rows(
  imp_nom_hist |> filter(ano >= ANO_HIST_INI),
  proj_rec     |> select(geo, ano, impostos_nominal)
) |> to_wide("impostos_nominal")

cresc_wide <- bind_rows(
  hist_cresc |> filter(ano > ANO_HIST_INI),
  proj_rec   |> select(geo, ano, tx_cresc_pib_real)
) |>
  mutate(tx_cresc_pib_real = round(tx_cresc_pib_real * 100, 2)) |>
  to_wide("tx_cresc_pib_real")

deflator_wide <- bind_rows(
  hist_deflator |> filter(ano > ANO_HIST_INI),
  proj_deflator
) |>
  mutate(deflator_pib = round(deflator_pib * 100, 2)) |>
  to_wide("deflator_pib")

# VAB macrossetor: histórico + projetado reconciliado
if (!is.null(vab_hist)) {
  vab_mac_full <- bind_rows(
    vab_hist |> select(geo, macrossetor, ano, vab_nominal = val_corrente),
    vab_mac  |> select(geo, macrossetor, ano, vab_nominal)
  )
} else {
  vab_mac_full <- vab_mac |> select(geo, macrossetor, ano, vab_nominal)
}

vab_macro_wide <- vab_mac_full |>
  filter(geo %in% GEO_ORDER) |>
  mutate(geo = factor(geo, levels = GEO_ORDER), vab_nominal = round(vab_nominal, 0)) |>
  arrange(macrossetor, ano) |>
  pivot_wider(names_from = geo, values_from = vab_nominal)

# VAB por atividade: histórico + projetado reconciliado (wide)
if (!is.null(vab_ativ_rec) && !is.null(vab_ativ_hist)) {
  vab_ativ_full <- bind_rows(
    vab_ativ_hist |>
      select(geo, atividade, ano, vab_nominal = val_corrente),
    vab_ativ_rec  |>
      select(geo, atividade, ano, vab_nominal)
  )
} else if (!is.null(vab_ativ_rec)) {
  vab_ativ_full <- vab_ativ_rec |> select(geo, atividade, ano, vab_nominal)
} else {
  vab_ativ_full <- NULL
}

ATIV_MACRO_MAP <- tibble(
  atividade   = ATIVIDADES,
  macrossetor = c(
    "agropecuaria",
    "industria", "industria", "industria", "industria",
    "servicos", "servicos", "servicos", "servicos", "servicos",
    "adm_publica",
    "servicos"
  )
)

vab_ativ_wide <- if (!is.null(vab_ativ_full)) {
  vab_ativ_full |>
    filter(geo %in% GEO_ORDER) |>
    left_join(ATIV_MACRO_MAP, by = "atividade") |>
    mutate(
      geo         = factor(geo, levels = GEO_ORDER),
      vab_nominal = round(vab_nominal, 0)
    ) |>
    arrange(macrossetor, atividade, ano) |>
    pivot_wider(names_from = geo, values_from = vab_nominal)
} else { NULL }

# IC em formato longo para aba dedicada
ic_long <- bind_rows(
  proj_rec |>
    left_join(pib_ci, by = c("geo", "ano")) |>
    transmute(geo, ano, variavel = "pib_nominal",
              ponto = round(pib_nominal, 0),
              li_95 = round(pib_lo95, 0),
              ls_95 = round(pib_hi95, 0)),
  proj_rec |>
    left_join(vab_total_ci, by = c("geo", "ano")) |>
    transmute(geo, ano, variavel = "vab_nominal_total",
              ponto = round(vab_nominal_total, 0),
              li_95 = round(vab_lo95, 0),
              ls_95 = round(vab_hi95, 0)),
  proj_rec |>
    left_join(imp_ci, by = c("geo", "ano")) |>
    transmute(geo, ano, variavel = "impostos_nominal",
              ponto = round(impostos_nominal, 0),
              li_95 = round(imp_lo95, 0),
              ls_95 = round(imp_hi95, 0)),
  proj_rec |>
    left_join(cresc_ci, by = c("geo", "ano")) |>
    transmute(geo, ano, variavel = "cresc_real_pib_pct",
              ponto = round(tx_cresc_pib_real * 100, 3),
              li_95 = round(cresc_lo95 * 100, 3),
              ls_95 = round(cresc_hi95 * 100, 3)),
  vab_mac_ci |>
    transmute(geo, ano,
              variavel = paste0("vab_", macrossetor),
              ponto = round(vab_nominal, 0),
              li_95 = round(vab_lo95, 0),
              ls_95 = round(vab_hi95, 0))
) |>
  filter(geo %in% GEO_ORDER) |>
  mutate(geo = factor(geo, levels = GEO_ORDER)) |>
  arrange(variavel, geo, ano)

# Adicionar IC das atividades ao ic_long
if (!is.null(vab_ativ_rec)) {
  ic_ativ <- vab_ativ_rec |>
    filter(geo %in% GEO_ORDER) |>
    transmute(geo, ano,
              variavel = paste0("vab_ativ_", atividade),
              ponto = round(vab_nominal, 0),
              li_95 = round(coalesce(vab_lo95, vab_nominal), 0),
              ls_95 = round(coalesce(vab_hi95, vab_nominal), 0)) |>
    mutate(geo = factor(geo, levels = GEO_ORDER))

  ic_long <- bind_rows(ic_long, ic_ativ) |>
    arrange(variavel, geo, ano)
}

# ==============================================================================
# Parte 4 — Exportar planilha Excel
# ==============================================================================

message("Gerando planilha Excel...")

st_header <- createStyle(fontSize = 11, fontColour = "#FFFFFF",
                          fgFill = "#1F497D", halign = "center",
                          textDecoration = "bold")
st_titulo <- createStyle(fontSize = 12, fontColour = "#1F497D",
                          textDecoration = "bold", halign = "left")
st_ano    <- createStyle(halign = "center", textDecoration = "bold")
st_num    <- createStyle(numFmt = "#,##0.00", halign = "right")
st_pct    <- createStyle(numFmt = "0.00",    halign = "right")
st_sep    <- createStyle(border = "Bottom",  borderColour = "#C0392B",
                          borderStyle = "medium")

escrever_aba <- function(wb, nome_aba, df, fmt = "num", titulo = NULL) {
  addWorksheet(wb, nome_aba)
  linha_dados <- 1L
  if (!is.null(titulo)) {
    writeData(wb, nome_aba, titulo, startRow = 1, startCol = 1)
    mergeCells(wb, nome_aba, rows = 1, cols = 1:ncol(df))
    addStyle(wb, nome_aba, st_titulo, rows = 1, cols = 1, stack = FALSE)
    linha_dados <- 2L
  }
  df_out <- rename(df, Ano = ano)
  writeData(wb, nome_aba, df_out, startRow = linha_dados)
  addStyle(wb, nome_aba, st_header,
           rows = linha_dados, cols = 1:ncol(df_out), gridExpand = TRUE)
  addStyle(wb, nome_aba, st_ano,
           rows = (linha_dados + 1):(linha_dados + nrow(df_out)),
           cols = 1, gridExpand = TRUE)
  st_val <- if (fmt == "pct") st_pct else st_num
  addStyle(wb, nome_aba, st_val,
           rows = (linha_dados + 1):(linha_dados + nrow(df_out)),
           cols = 2:ncol(df_out), gridExpand = TRUE)
  n_hist <- sum(df$ano <= ANO_HIST_FIM)
  if (n_hist > 0 && n_hist < nrow(df)) {
    addStyle(wb, nome_aba, st_sep,
             rows = linha_dados + n_hist,
             cols = 1:ncol(df_out), gridExpand = TRUE, stack = TRUE)
  }
  freezePane(wb, nome_aba, firstActiveRow = linha_dados + 1L, firstActiveCol = 2L)
  setColWidths(wb, nome_aba, cols = 1,              widths = 6)
  setColWidths(wb, nome_aba, cols = 2:ncol(df_out), widths = 14)
  invisible(wb)
}

wb <- createWorkbook()

wb <- escrever_aba(wb, "PIB_nominal", pib_wide,
                   titulo = "PIB nominal — R$ milhões (correntes)")
wb <- escrever_aba(wb, "VAB_nominal", vab_wide,
                   titulo = "VAB nominal — R$ milhões (correntes)")
wb <- escrever_aba(wb, "Impostos_nominais", imp_wide,
                   titulo = "Impostos líquidos de subsídios — R$ milhões (correntes)")
wb <- escrever_aba(wb, "Cresc_real_PIB", cresc_wide,
                   fmt = "pct",
                   titulo = "Taxa de crescimento real do PIB — % a.a.")
wb <- escrever_aba(wb, "Deflator_PIB", deflator_wide,
                   fmt = "pct",
                   titulo = "Deflator implícito do PIB — % a.a.")

# Aba VAB macrossetor (histórico + projetado)
addWorksheet(wb, "VAB_macrossetor")
writeData(wb, "VAB_macrossetor",
          "VAB por macrossetor — R$ milhões (histórico 2002–2023 + projetado 2024–2031)",
          startRow = 1, startCol = 1)
mergeCells(wb, "VAB_macrossetor", rows = 1, cols = 1:ncol(vab_macro_wide))
addStyle(wb, "VAB_macrossetor", st_titulo, rows = 1, cols = 1)
writeData(wb, "VAB_macrossetor", vab_macro_wide, startRow = 2)
addStyle(wb, "VAB_macrossetor", st_header,
         rows = 2, cols = 1:ncol(vab_macro_wide), gridExpand = TRUE)
addStyle(wb, "VAB_macrossetor", st_num,
         rows = 3:(2 + nrow(vab_macro_wide)),
         cols = 3:ncol(vab_macro_wide), gridExpand = TRUE)
n_hist_mac <- sum(vab_macro_wide$ano <= ANO_HIST_FIM, na.rm = TRUE)
if (n_hist_mac > 0 && n_hist_mac < nrow(vab_macro_wide)) {
  addStyle(wb, "VAB_macrossetor", st_sep,
           rows = 2 + n_hist_mac, cols = 1:ncol(vab_macro_wide),
           gridExpand = TRUE, stack = TRUE)
}
freezePane(wb, "VAB_macrossetor", firstActiveRow = 3L, firstActiveCol = 3L)
setColWidths(wb, "VAB_macrossetor", cols = 1:2, widths = 16)
setColWidths(wb, "VAB_macrossetor", cols = 3:ncol(vab_macro_wide), widths = 14)

# Aba VAB_atividade (histórico + projetado por atividade individual)
if (!is.null(vab_ativ_wide)) {
  addWorksheet(wb, "VAB_atividade")
  writeData(wb, "VAB_atividade",
            "VAB por atividade econômica — R$ milhões (histórico 2002–2023 + projetado 2024–2031)",
            startRow = 1, startCol = 1)
  mergeCells(wb, "VAB_atividade", rows = 1, cols = 1:ncol(vab_ativ_wide))
  addStyle(wb, "VAB_atividade", st_titulo, rows = 1, cols = 1)
  writeData(wb, "VAB_atividade", vab_ativ_wide, startRow = 2)
  addStyle(wb, "VAB_atividade", st_header,
           rows = 2, cols = 1:ncol(vab_ativ_wide), gridExpand = TRUE)
  addStyle(wb, "VAB_atividade", st_num,
           rows = 3:(2 + nrow(vab_ativ_wide)),
           cols = 4:ncol(vab_ativ_wide), gridExpand = TRUE)
  n_hist_ativ <- sum(vab_ativ_wide$ano <= ANO_HIST_FIM, na.rm = TRUE)
  if (n_hist_ativ > 0 && n_hist_ativ < nrow(vab_ativ_wide)) {
    addStyle(wb, "VAB_atividade", st_sep,
             rows = 2 + n_hist_ativ, cols = 1:ncol(vab_ativ_wide),
             gridExpand = TRUE, stack = TRUE)
  }
  freezePane(wb, "VAB_atividade", firstActiveRow = 3L, firstActiveCol = 4L)
  setColWidths(wb, "VAB_atividade", cols = 1:3, widths = c(16, 24, 6))
  setColWidths(wb, "VAB_atividade", cols = 4:ncol(vab_ativ_wide), widths = 14)
}

# Aba Intervalos_Confianca (formato longo, período projetado, IC 95%)
addWorksheet(wb, "Intervalos_Confianca")
writeData(wb, "Intervalos_Confianca",
          paste0("Intervalos de confiança 95% — Projeções ",
                 ANO_HIST_FIM + 1L, "–", ANO_PROJ_FIM,
                 " | pib_nominal, vab_nominal_total, impostos_nominal, ",
                 "cresc_real_pib_pct, vab_{macrossetor}, vab_ativ_{atividade}"),
          startRow = 1, startCol = 1)
mergeCells(wb, "Intervalos_Confianca", rows = 1, cols = 1:6)
addStyle(wb, "Intervalos_Confianca", st_titulo, rows = 1, cols = 1)
ic_df <- ic_long |>
  mutate(geo = as.character(geo)) |>
  rename(`Territorio` = geo, `Ano` = ano, `Variavel` = variavel,
         `Ponto_central` = ponto, `LI_95pct` = li_95, `LS_95pct` = ls_95)
writeData(wb, "Intervalos_Confianca", ic_df, startRow = 2)
addStyle(wb, "Intervalos_Confianca", st_header,
         rows = 2, cols = 1:ncol(ic_df), gridExpand = TRUE)
addStyle(wb, "Intervalos_Confianca", st_num,
         rows = 3:(2 + nrow(ic_df)), cols = 4:6, gridExpand = TRUE)
freezePane(wb, "Intervalos_Confianca", firstActiveRow = 3L, firstActiveCol = 2L)
setColWidths(wb, "Intervalos_Confianca", cols = 1:3, widths = c(22, 6, 24))
setColWidths(wb, "Intervalos_Confianca", cols = 4:6, widths = 16)

# Aba Selecao_Modelos
if (!is.null(params_mod)) {
  rotulos_variavel <- c(
    idx_volume   = "Índice de Volume (VAB real)",
    idx_preco    = "Índice de Preço (Deflator)",
    log_impostos = "Impostos nominais (log)"
  )
  rotulos_macro <- c(
    agropecuaria = "Agropecuária",
    industria    = "Indústria",
    adm_publica  = "Adm. Pública",
    servicos     = "Serviços",
    total        = "Total (impostos)"
  )
  tab_modelos <- params_mod |>
    mutate(
      variavel_lbl = rotulos_variavel[variavel],
      setor_lbl    = case_when(
        !is.na(atividade) ~
          paste0("Ativ: ", coalesce(ATIVIDADE_LABEL[atividade], atividade)),
        !is.na(macrossetor) ~
          paste0("Macro: ", coalesce(rotulos_macro[macrossetor], macrossetor)),
        TRUE ~ NA_character_
      ),
      mase_melhor = round(mase_melhor, 4),
      rmse_melhor = round(rmse_melhor, 6)
    ) |>
    select(
      `Unidade Geografica` = geo,
      `Setor/Atividade`    = setor_lbl,
      `Variavel`           = variavel_lbl,
      `Modelo`             = modelo,
      `Parametros`         = parametros,
      `MASE`               = mase_melhor,
      `RMSE`               = rmse_melhor
    ) |>
    arrange(`Unidade Geografica`, `Setor/Atividade`, `Variavel`)
  addWorksheet(wb, "Selecao_Modelos")
  writeData(wb, "Selecao_Modelos",
            "Selecao de modelos — melhor modelo por serie (validacao cruzada, metrica MASE)",
            startRow = 1, startCol = 1)
  mergeCells(wb, "Selecao_Modelos", rows = 1, cols = 1:ncol(tab_modelos))
  addStyle(wb, "Selecao_Modelos", st_titulo, rows = 1, cols = 1)
  writeData(wb, "Selecao_Modelos", tab_modelos, startRow = 2)
  addStyle(wb, "Selecao_Modelos", st_header,
           rows = 2, cols = 1:ncol(tab_modelos), gridExpand = TRUE)
  addStyle(wb, "Selecao_Modelos", st_num,
           rows = 3:(2 + nrow(tab_modelos)), cols = 6:7, gridExpand = TRUE)
  freezePane(wb, "Selecao_Modelos", firstActiveRow = 3L, firstActiveCol = 2L)
  setColWidths(wb, "Selecao_Modelos", cols = 1:5, widths = c(22, 24, 28, 14, 28))
  setColWidths(wb, "Selecao_Modelos", cols = 6:7, widths = c(10, 12))
}

saveWorkbook(wb, "output/tabelas/projecoes_pib_estadual.xlsx", overwrite = TRUE)
message("Salvo: output/tabelas/projecoes_pib_estadual.xlsx")

# ==============================================================================
# Parte 5 — Gráficos
# ==============================================================================

message("Gerando gráficos...")

# ----- Tema -------------------------------------------------------------------
tema <- theme_minimal(base_size = 10) +
  theme(
    plot.title       = element_text(face = "bold", size = 11),
    plot.subtitle    = element_text(colour = "grey40", size = 9),
    plot.caption     = element_text(colour = "grey55", size = 7),
    panel.grid.minor = element_blank(),
    legend.position  = "bottom",
    strip.text       = element_text(face = "bold", size = 8),
    axis.text        = element_text(size = 7)
  )

COR_HIST  <- "#1F497D"
COR_PROJ  <- "#C0392B"
COR_RIBBN <- "#C0392B"

PALETA_MACRO <- c(
  agropecuaria = "#2E8B57",
  industria    = "#E67E22",
  adm_publica  = "#8E44AD",
  servicos     = "#2980B9"
)

MACRO_LABEL <- c(
  agropecuaria = "Agropecuária",
  industria    = "Indústria",
  adm_publica  = "Adm. Pública",
  servicos     = "Serviços"
)

vl <- geom_vline(xintercept = ANO_HIST_FIM + 0.5,
                 linetype = "dashed", colour = "grey55", linewidth = 0.4)

# ----- Preparar dados combinados histórico + projetado ----------------------

# PIB nominal
pib_comb <- bind_rows(
  pib_nom_hist |>
    filter(ano >= ANO_HIST_INI, geo %in% GEO_ORDER) |>
    transmute(geo, ano, valor = pib_nominal, lo95 = NA_real_, hi95 = NA_real_,
              tipo = "Histórico"),
  proj_rec |>
    filter(geo %in% GEO_ORDER) |>
    left_join(pib_ci, by = c("geo", "ano")) |>
    transmute(geo, ano, valor = pib_nominal, lo95 = pib_lo95, hi95 = pib_hi95,
              tipo = "Projetado")
) |> mutate(geo = factor(geo, levels = GEO_ORDER))

# VAB nominal total
vab_comb <- bind_rows(
  vab_nom_hist |>
    filter(ano >= ANO_HIST_INI, geo %in% GEO_ORDER) |>
    transmute(geo, ano, valor = vab_nominal, lo95 = NA_real_, hi95 = NA_real_,
              tipo = "Histórico"),
  proj_rec |>
    filter(geo %in% GEO_ORDER) |>
    left_join(vab_total_ci, by = c("geo", "ano")) |>
    transmute(geo, ano, valor = vab_nominal_total, lo95 = vab_lo95, hi95 = vab_hi95,
              tipo = "Projetado")
) |> mutate(geo = factor(geo, levels = GEO_ORDER))

# Impostos nominais
imp_comb <- bind_rows(
  imp_nom_hist |>
    filter(ano >= ANO_HIST_INI, geo %in% GEO_ORDER) |>
    transmute(geo, ano, valor = impostos_nominal, lo95 = NA_real_, hi95 = NA_real_,
              tipo = "Histórico"),
  proj_rec |>
    filter(geo %in% GEO_ORDER) |>
    left_join(imp_ci, by = c("geo", "ano")) |>
    transmute(geo, ano, valor = impostos_nominal, lo95 = imp_lo95, hi95 = imp_hi95,
              tipo = "Projetado")
) |> mutate(geo = factor(geo, levels = GEO_ORDER))

# Crescimento real PIB (%)
cresc_comb <- bind_rows(
  hist_cresc |>
    filter(ano >= ANO_HIST_INI + 1L, geo %in% GEO_ORDER) |>
    transmute(geo, ano, valor = tx_cresc_pib_real * 100, lo95 = NA_real_, hi95 = NA_real_,
              tipo = "Histórico"),
  proj_rec |>
    filter(geo %in% GEO_ORDER) |>
    left_join(cresc_ci, by = c("geo", "ano")) |>
    transmute(geo, ano, valor = tx_cresc_pib_real * 100,
              lo95 = cresc_lo95 * 100, hi95 = cresc_hi95 * 100,
              tipo = "Projetado")
) |> mutate(geo = factor(geo, levels = GEO_ORDER))

# Deflator PIB (%)
defl_comb <- bind_rows(
  hist_deflator |>
    filter(ano >= ANO_HIST_INI + 1L, geo %in% GEO_ORDER) |>
    transmute(geo, ano, valor = deflator_pib * 100, lo95 = NA_real_, hi95 = NA_real_,
              tipo = "Histórico"),
  proj_deflator |>
    filter(geo %in% GEO_ORDER) |>
    transmute(geo, ano, valor = deflator_pib * 100, lo95 = NA_real_, hi95 = NA_real_,
              tipo = "Projetado")
) |> mutate(geo = factor(geo, levels = GEO_ORDER))

# VAB por macrossetor (histórico + projetado com CI)
vab_mac_comb <- bind_rows(
  if (!is.null(vab_hist)) {
    vab_hist |>
      filter(geo %in% GEO_ORDER) |>
      transmute(geo, macrossetor, ano, valor = val_corrente,
                lo95 = NA_real_, hi95 = NA_real_, tipo = "Histórico")
  } else { tibble() },
  vab_mac_ci |>
    filter(geo %in% GEO_ORDER) |>
    transmute(geo, macrossetor, ano, valor = vab_nominal,
              lo95 = vab_lo95, hi95 = vab_hi95, tipo = "Projetado")
) |>
  mutate(geo = factor(geo, levels = GEO_ORDER),
         macro_label = MACRO_LABEL[macrossetor])

# ----- Função genérica: plot facetado por geo --------------------------------
plot_facet_geo <- function(df, y_label, titulo, subtitulo, ncol = 6,
                           fmt_y = "number", divisor = 1) {
  df_plot <- df |>
    mutate(valor_plot = valor / divisor,
           lo_plot    = lo95  / divisor,
           hi_plot    = hi95  / divisor)
  gg <- ggplot(df_plot, aes(x = ano)) +
    geom_ribbon(
      aes(ymin = lo_plot, ymax = hi_plot),
      data = \(d) filter(d, tipo == "Projetado", !is.na(lo_plot)),
      fill = COR_RIBBN, alpha = 0.18
    ) +
    vl +
    geom_line(aes(y = valor_plot, colour = tipo), linewidth = 0.65) +
    scale_colour_manual(
      values = c(Histórico = COR_HIST, Projetado = COR_PROJ), name = NULL
    ) +
    scale_x_continuous(breaks = c(2005, 2015, ANO_PROJ_FIM)) +
    {
      if (fmt_y == "pct")
        scale_y_continuous(labels = scales::label_number(suffix = "%",
                                                          decimal.mark = ",",
                                                          accuracy = 0.1))
      else
        scale_y_continuous(labels = scales::label_number(big.mark = ".",
                                                          decimal.mark = ",",
                                                          accuracy = 1))
    } +
    facet_wrap(~geo, ncol = ncol, scales = "free_y") +
    labs(title = titulo, subtitle = subtitulo,
         x = NULL, y = y_label,
         caption = "Fonte: IBGE (histórico 2002–2023); projeção própria (2024–2031) com IC 95%.") +
    tema
  gg
}

# ==============================================================================
# 5.1 — Gráficos "todas_geos": 1 plot por variável, todos os 33 territórios
# ==============================================================================

message("  Gerando plots todas_geos (9 arquivos)...")

g_pib <- plot_facet_geo(
  pib_comb, "R$ bilhões",
  "PIB Nominal — Todos os territórios",
  "R$ bilhões (correntes) | Histórico 2002–2023 + Projeção 2024–2031 com IC 95%",
  divisor = 1e3
)
ggsave("output/graficos/todas_geos/pib_nominal.png",
       g_pib, width = 22, height = 22, dpi = 150)

g_vab <- plot_facet_geo(
  vab_comb, "R$ bilhões",
  "VAB Nominal Total — Todos os territórios",
  "R$ bilhões (correntes) | Histórico 2002–2023 + Projeção 2024–2031 com IC 95%",
  divisor = 1e3
)
ggsave("output/graficos/todas_geos/vab_nominal.png",
       g_vab, width = 22, height = 22, dpi = 150)

g_imp <- plot_facet_geo(
  imp_comb, "R$ bilhões",
  "Impostos Líquidos de Subsídios — Todos os territórios",
  "R$ bilhões (correntes) | Histórico 2002–2023 + Projeção 2024–2031 com IC 95%",
  divisor = 1e3
)
ggsave("output/graficos/todas_geos/impostos_nominal.png",
       g_imp, width = 22, height = 22, dpi = 150)

g_cresc <- plot_facet_geo(
  cresc_comb, "% a.a.",
  "Crescimento Real do PIB — Todos os territórios",
  "% a.a. | Histórico 2003–2023 + Projeção 2024–2031 com IC 95%",
  fmt_y = "pct"
)
ggsave("output/graficos/todas_geos/cresc_real_pib.png",
       g_cresc, width = 22, height = 22, dpi = 150)

g_defl <- plot_facet_geo(
  defl_comb, "% a.a.",
  "Deflator Implícito do PIB — Todos os territórios",
  "% a.a. (variação yoy) | Histórico 2003–2023 + Projeção 2024–2031",
  fmt_y = "pct"
)
ggsave("output/graficos/todas_geos/deflator_pib.png",
       g_defl, width = 22, height = 22, dpi = 150)

# VAB por macrossetor — um plot por macrossetor (todos os geos)
for (mac in names(MACRO_LABEL)) {
  df_m <- vab_mac_comb |> filter(macrossetor == mac)
  g_m <- plot_facet_geo(
    df_m |> select(geo, ano, valor, lo95, hi95, tipo), "R$ bilhões",
    paste0("VAB — ", MACRO_LABEL[mac], " — Todos os territórios"),
    "R$ bilhões (correntes) | Histórico 2002–2023 + Projeção 2024–2031 com IC 95%",
    divisor = 1e3
  )
  ggsave(paste0("output/graficos/todas_geos/vab_", mac, ".png"),
         g_m, width = 22, height = 22, dpi = 150)
}
message("    todas_geos: 9 arquivos gerados (macro/agregados).")

# VAB por atividade individual — um plot por atividade (todos os geos)
if (!is.null(vab_ativ_rec)) {
  vab_ativ_comb <- bind_rows(
    if (!is.null(vab_ativ_hist)) {
      vab_ativ_hist |>
        filter(geo %in% GEO_ORDER) |>
        transmute(geo, atividade, ano, valor = val_corrente,
                  lo95 = NA_real_, hi95 = NA_real_, tipo = "Histórico")
    } else { tibble() },
    vab_ativ_rec |>
      filter(geo %in% GEO_ORDER) |>
      transmute(geo, atividade, ano, valor = vab_nominal,
                lo95 = coalesce(vab_lo95, vab_nominal),
                hi95 = coalesce(vab_hi95, vab_nominal),
                tipo = "Projetado")
  ) |>
    mutate(geo = factor(geo, levels = GEO_ORDER))

  for (ativ in ATIVIDADES) {
    df_a <- vab_ativ_comb |> filter(atividade == ativ)
    if (nrow(df_a) == 0) next
    g_a <- plot_facet_geo(
      df_a |> select(geo, ano, valor, lo95, hi95, tipo), "R$ bilhões",
      paste0("VAB — ", ATIVIDADE_LABEL[ativ], " — Todos os territórios"),
      "R$ bilhões (correntes) | Histórico 2002–2023 + Projeção 2024–2031 com IC 95%",
      divisor = 1e3
    )
    ggsave(paste0("output/graficos/todas_geos/vab_ativ_", ativ, ".png"),
           g_a, width = 22, height = 22, dpi = 150)
  }
  message("    todas_geos: 12 plots de atividades gerados.")
}

# ==============================================================================
# 5.2 — Gráficos "por_geo": 33 plots com todas as variáveis por território
# ==============================================================================

message("  Gerando plots por_geo (33 arquivos)...")

# Montar dados em long para cada geo (9 variáveis: 5 agg + 4 macro)
make_geo_long <- function(geo_name) {
  g <- geo_name
  bind_rows(
    pib_comb |>
      filter(geo == g) |>
      transmute(geo, ano, valor = valor / 1e3, lo95 = lo95 / 1e3, hi95 = hi95 / 1e3,
                tipo, variavel = "PIB nominal (R$ bi)"),
    vab_comb |>
      filter(geo == g) |>
      transmute(geo, ano, valor = valor / 1e3, lo95 = lo95 / 1e3, hi95 = hi95 / 1e3,
                tipo, variavel = "VAB nominal (R$ bi)"),
    imp_comb |>
      filter(geo == g) |>
      transmute(geo, ano, valor = valor / 1e3, lo95 = lo95 / 1e3, hi95 = hi95 / 1e3,
                tipo, variavel = "Impostos nominais (R$ bi)"),
    cresc_comb |>
      filter(geo == g) |>
      transmute(geo, ano, valor, lo95, hi95, tipo, variavel = "Cresc. real PIB (%)"),
    defl_comb |>
      filter(geo == g) |>
      transmute(geo, ano, valor, lo95, hi95, tipo, variavel = "Deflator PIB (%)"),
    vab_mac_comb |>
      filter(geo == g) |>
      transmute(geo, ano, valor = valor / 1e3, lo95 = lo95 / 1e3, hi95 = hi95 / 1e3,
                tipo, variavel = paste0("VAB ", macro_label, " (R$ bi)"))
  ) |>
    mutate(variavel = factor(variavel, levels = c(
      "PIB nominal (R$ bi)", "VAB nominal (R$ bi)", "Impostos nominais (R$ bi)",
      "Cresc. real PIB (%)", "Deflator PIB (%)",
      paste0("VAB ", MACRO_LABEL, " (R$ bi)")
    )))
}

for (geo_name in GEO_ORDER) {
  df_geo <- make_geo_long(geo_name)
  if (nrow(df_geo) == 0) next

  geo_safe <- iconv(geo_name, to = "ASCII//TRANSLIT")
  geo_safe <- gsub("[^a-zA-Z0-9_]", "_", geo_safe)

  g_geo <- ggplot(df_geo, aes(x = ano)) +
    geom_ribbon(
      aes(ymin = lo95, ymax = hi95),
      data = \(d) filter(d, tipo == "Projetado", !is.na(lo95)),
      fill = COR_RIBBN, alpha = 0.20
    ) +
    vl +
    geom_hline(
      data = \(d) filter(d, str_detect(variavel, "Cresc|Deflator")),
      yintercept = 0, colour = "grey70", linewidth = 0.3, linetype = "dotted"
    ) +
    geom_line(aes(y = valor, colour = tipo), linewidth = 0.85) +
    scale_colour_manual(
      values = c(Histórico = COR_HIST, Projetado = COR_PROJ), name = NULL
    ) +
    scale_x_continuous(breaks = c(2005, 2010, 2015, 2020, ANO_PROJ_FIM)) +
    scale_y_continuous(labels = scales::label_number(big.mark = ".", decimal.mark = ",")) +
    facet_wrap(~variavel, ncol = 3, scales = "free_y") +
    labs(
      title    = geo_name,
      subtitle = "Histórico (2002–2023) + Projeção (2024–2031) com IC 95%",
      x = NULL, y = NULL,
      caption  = "Fonte: IBGE (histórico); projeção própria com reconciliação top-down."
    ) +
    tema +
    theme(legend.position = "bottom")

  ggsave(paste0("output/graficos/por_geo/", geo_safe, ".png"),
         g_geo, width = 16, height = 14, dpi = 150)
}
message("    por_geo: 33 arquivos gerados.")

# ==============================================================================
# 5.3 — Gráficos "series_brutas": séries modeladas diretamente com CI
# ==============================================================================

message("  Gerando plots series_brutas (9 arquivos)...")

# Histórico idx por macrossetor (de vab_macro_hist.rds)
if (!is.null(vab_hist)) {
  for (mac in names(MACRO_LABEL)) {
    # idx_volume
    df_vol_hist <- vab_hist |>
      filter(macrossetor == mac, !is.na(idx_volume), geo %in% GEO_ORDER) |>
      transmute(geo, ano, valor = idx_volume, lo95 = NA_real_, hi95 = NA_real_,
                tipo = "Histórico")
    df_vol_proj <- proj_brutas |>
      filter(macrossetor == mac, variavel == "idx_volume", geo %in% GEO_ORDER) |>
      transmute(geo, ano, valor = proj,
                lo95 = coalesce(lo95, proj), hi95 = coalesce(hi95, proj),
                tipo = "Projetado")
    df_vol <- bind_rows(df_vol_hist, df_vol_proj) |>
      mutate(geo = factor(geo, levels = GEO_ORDER))

    g_vol <- ggplot(df_vol, aes(x = ano)) +
      geom_ribbon(
        aes(ymin = lo95, ymax = hi95),
        data = \(d) filter(d, tipo == "Projetado"),
        fill = COR_RIBBN, alpha = 0.20
      ) +
      vl +
      geom_hline(yintercept = 1, colour = "grey60", linewidth = 0.3, linetype = "dotted") +
      geom_line(aes(y = valor, colour = tipo), linewidth = 0.65) +
      scale_colour_manual(
        values = c(Histórico = COR_HIST, Projetado = COR_PROJ), name = NULL
      ) +
      scale_x_continuous(breaks = c(2005, 2015, ANO_PROJ_FIM)) +
      facet_wrap(~geo, ncol = 6, scales = "free_y") +
      labs(
        title    = paste0("Índice de Volume — ", MACRO_LABEL[mac]),
        subtitle = "Razão yoy (= 1 + tx. cresc. real) | Histórico 2003–2023 + Projeção 2024–2031 com IC 95%",
        x = NULL, y = "idx volume",
        caption  = "Fonte: IBGE (histórico); projeção própria."
      ) +
      tema
    ggsave(paste0("output/graficos/series_brutas/idx_volume_", mac, ".png"),
           g_vol, width = 22, height = 22, dpi = 150)

    # idx_preco
    df_prc_hist <- vab_hist |>
      filter(macrossetor == mac, !is.na(idx_preco), geo %in% GEO_ORDER) |>
      transmute(geo, ano, valor = idx_preco, lo95 = NA_real_, hi95 = NA_real_,
                tipo = "Histórico")
    df_prc_proj <- proj_brutas |>
      filter(macrossetor == mac, variavel == "idx_preco", geo %in% GEO_ORDER) |>
      transmute(geo, ano, valor = proj,
                lo95 = coalesce(lo95, proj), hi95 = coalesce(hi95, proj),
                tipo = "Projetado")
    df_prc <- bind_rows(df_prc_hist, df_prc_proj) |>
      mutate(geo = factor(geo, levels = GEO_ORDER))

    g_prc <- ggplot(df_prc, aes(x = ano)) +
      geom_ribbon(
        aes(ymin = lo95, ymax = hi95),
        data = \(d) filter(d, tipo == "Projetado"),
        fill = COR_RIBBN, alpha = 0.20
      ) +
      vl +
      geom_hline(yintercept = 1, colour = "grey60", linewidth = 0.3, linetype = "dotted") +
      geom_line(aes(y = valor, colour = tipo), linewidth = 0.65) +
      scale_colour_manual(
        values = c(Histórico = COR_HIST, Projetado = COR_PROJ), name = NULL
      ) +
      scale_x_continuous(breaks = c(2005, 2015, ANO_PROJ_FIM)) +
      facet_wrap(~geo, ncol = 6, scales = "free_y") +
      labs(
        title    = paste0("Índice de Preço — ", MACRO_LABEL[mac]),
        subtitle = "Razão yoy (≈ 1 + inflação setorial) | Histórico 2003–2023 + Projeção 2024–2031 com IC 95%",
        x = NULL, y = "idx preço",
        caption  = "Fonte: IBGE (histórico); projeção própria."
      ) +
      tema
    ggsave(paste0("output/graficos/series_brutas/idx_preco_", mac, ".png"),
           g_prc, width = 22, height = 22, dpi = 150)
  }
}

# log(impostos) — série bruta modelada
df_imp_hist <- imp_nom_hist |>
  filter(geo %in% GEO_ORDER, impostos_nominal > 0) |>
  transmute(geo, ano, valor = log(impostos_nominal), lo95 = NA_real_, hi95 = NA_real_,
            tipo = "Histórico")
df_imp_proj <- proj_brutas |>
  filter(variavel == "log_impostos", geo %in% GEO_ORDER) |>
  transmute(geo, ano, valor = proj,
            lo95 = coalesce(lo95, proj), hi95 = coalesce(hi95, proj),
            tipo = "Projetado")
df_imp_raw <- bind_rows(df_imp_hist, df_imp_proj) |>
  mutate(geo = factor(geo, levels = GEO_ORDER))

g_imp_raw <- ggplot(df_imp_raw, aes(x = ano)) +
  geom_ribbon(
    aes(ymin = lo95, ymax = hi95),
    data = \(d) filter(d, tipo == "Projetado"),
    fill = COR_RIBBN, alpha = 0.20
  ) +
  vl +
  geom_line(aes(y = valor, colour = tipo), linewidth = 0.65) +
  scale_colour_manual(
    values = c(Histórico = COR_HIST, Projetado = COR_PROJ), name = NULL
  ) +
  scale_x_continuous(breaks = c(2005, 2015, ANO_PROJ_FIM)) +
  facet_wrap(~geo, ncol = 6, scales = "free_y") +
  labs(
    title    = "Log(Impostos Nominais) — série bruta modelada",
    subtitle = "log(R$ milhões) | Histórico 2002–2023 + Projeção 2024–2031 com IC 95%",
    x = NULL, y = "log(impostos)",
    caption  = "Fonte: IBGE (histórico); projeção própria."
  ) +
  tema
ggsave("output/graficos/series_brutas/log_impostos.png",
       g_imp_raw, width = 22, height = 22, dpi = 150)

message("    series_brutas: arquivos gerados.")

# ==============================================================================
# 5.4 — Gráficos "por_geo_atividade": 33 stacked-area plots por território
# ==============================================================================

if (!is.null(vab_ativ_full)) {
  message("  Gerando plots por_geo_atividade (33 arquivos)...")

  # Paleta fixa para 12 atividades (RColorBrewer "Paired" tem exatamente 12)
  PALETA_ATIV <- setNames(
    RColorBrewer::brewer.pal(12, "Paired"),
    ATIVIDADES
  )

  for (geo_name in GEO_ORDER) {
    df_ga <- vab_ativ_full |>
      filter(geo == geo_name) |>
      mutate(
        ativ_label = factor(ATIVIDADE_LABEL[atividade], levels = ATIVIDADE_LABEL),
        tipo       = if_else(ano <= ANO_HIST_FIM, "Histórico", "Projetado")
      )
    if (nrow(df_ga) == 0) next

    geo_safe <- iconv(geo_name, to = "ASCII//TRANSLIT")
    geo_safe <- gsub("[^a-zA-Z0-9_]", "_", geo_safe)

    g_ga <- ggplot(df_ga,
                   aes(x = ano, y = vab_nominal / 1e3, fill = ativ_label)) +
      geom_area(position = "stack", alpha = 0.85) +
      vl +
      scale_fill_manual(values = setNames(PALETA_ATIV, ATIVIDADE_LABEL),
                        name = "Atividade") +
      scale_x_continuous(breaks = c(2005, 2010, 2015, 2020, ANO_PROJ_FIM)) +
      scale_y_continuous(
        labels = scales::label_number(big.mark = ".", decimal.mark = ",")
      ) +
      labs(
        title    = paste0("VAB por Atividade — ", geo_name),
        subtitle = paste0("R$ bilhões (correntes) | Histórico ",
                          ANO_HIST_INI, "–", ANO_HIST_FIM,
                          " + Projeção ", ANO_HIST_FIM + 1L, "–", ANO_PROJ_FIM),
        x = NULL, y = "R$ bilhões",
        caption  = "Fonte: IBGE (histórico); projeção própria com reconciliação top-down."
      ) +
      tema +
      theme(legend.position = "right",
            legend.key.size  = unit(0.4, "cm"),
            legend.text      = element_text(size = 7))

    ggsave(
      paste0("output/graficos/por_geo_atividade/", geo_safe, ".png"),
      g_ga, width = 14, height = 7, dpi = 150
    )
  }
  message("    por_geo_atividade: 33 arquivos gerados.")
}

# ==============================================================================
# 5.5 — Gráficos de resumo (todas as regiões/Brasil, comparativos)
# ==============================================================================

REGIOES_BR <- c("Brasil", "Norte", "Nordeste", "Sudeste", "Sul", "Centro-Oeste")

# G1: PIB nominal Brasil (histórico + projetado com CI)
pib_brasil_ts <- pib_comb |>
  filter(geo == "Brasil") |>
  mutate(tipo = factor(tipo, levels = c("Histórico", "Projetado")))

g1 <- ggplot(pib_brasil_ts, aes(x = ano)) +
  geom_ribbon(aes(ymin = lo95 / 1e6, ymax = hi95 / 1e6),
              data = \(d) filter(d, tipo == "Projetado", !is.na(lo95)),
              fill = COR_RIBBN, alpha = 0.20) +
  vl +
  geom_line(aes(y = valor / 1e6, colour = tipo), linewidth = 1.1) +
  geom_point(aes(y = valor / 1e6, colour = tipo), size = 2.0) +
  scale_colour_manual(values = c(Histórico = COR_HIST, Projetado = COR_PROJ), name = NULL) +
  scale_x_continuous(breaks = seq(ANO_HIST_INI, ANO_PROJ_FIM, 2)) +
  scale_y_continuous(labels = scales::label_number(suffix = " tri", accuracy = 0.1)) +
  labs(title    = "PIB Nominal — Brasil",
       subtitle = "R$ trilhões (valores correntes) | IC 95% no período projetado",
       x = NULL, y = NULL,
       caption  = "Fonte: IBGE (histórico 2002–2023); projeção própria (2024–2031).") +
  tema
ggsave("output/graficos/pib_nominal_brasil.png", g1, width = 10, height = 6, dpi = 150)

# G2: Crescimento real por região (barras, período projetado)
cresc_regioes <- cresc_comb |>
  filter(geo %in% REGIOES_BR, tipo == "Projetado") |>
  mutate(geo = factor(geo, levels = REGIOES_BR))

g2 <- ggplot(cresc_regioes, aes(x = ano, y = valor, fill = geo)) +
  geom_col(position = position_dodge(0.8), width = 0.75) +
  geom_hline(yintercept = 0, colour = "black", linewidth = 0.3) +
  scale_fill_brewer(palette = "Set2", name = NULL) +
  scale_x_continuous(breaks = seq(ANO_HIST_FIM + 1L, ANO_PROJ_FIM)) +
  labs(title    = "Taxa de Crescimento Real do PIB — Brasil e Regiões",
       subtitle = "Projeção 2024–2031 (% a.a.)",
       x = NULL, y = "% a.a.",
       caption  = "Projeção própria com reconciliação top-down.") +
  tema
ggsave("output/graficos/cresc_real_regioes.png", g2, width = 12, height = 6, dpi = 150)

# G3: PIB nominal Roraima (com CI)
pib_rr_ts <- pib_comb |> filter(geo == "Roraima")

g3 <- ggplot(pib_rr_ts, aes(x = ano)) +
  geom_ribbon(aes(ymin = lo95 / 1e3, ymax = hi95 / 1e3),
              data = \(d) filter(d, tipo == "Projetado", !is.na(lo95)),
              fill = COR_RIBBN, alpha = 0.20) +
  vl +
  geom_line(aes(y = valor / 1e3, colour = tipo), linewidth = 1.1) +
  geom_point(aes(y = valor / 1e3, colour = tipo), size = 2.0) +
  scale_colour_manual(values = c(Histórico = COR_HIST, Projetado = COR_PROJ), name = NULL) +
  scale_x_continuous(breaks = seq(ANO_HIST_INI, ANO_PROJ_FIM, 2)) +
  scale_y_continuous(labels = scales::label_number(suffix = " bi", accuracy = 0.1)) +
  labs(title    = "PIB Nominal — Roraima",
       subtitle = "R$ bilhões (valores correntes) | IC 95% no período projetado",
       x = NULL, y = NULL,
       caption  = "Fonte: IBGE (histórico 2002–2023); projeção própria (2024–2031).") +
  tema
ggsave("output/graficos/pib_nominal_roraima.png", g3, width = 10, height = 6, dpi = 150)

# G4: Fatores de ajuste da reconciliação
fat_adj <- proj_rec |>
  filter(!is.na(fator_ajuste)) |>
  mutate(
    desvio_pct = (fator_ajuste - 1) * 100,
    nivel = case_when(
      geo_tipo == "brasil" ~ "Brasil",
      geo_tipo == "regiao" ~ "Regiões",
      TRUE                 ~ "Estados"
    )
  )

g4 <- ggplot(fat_adj, aes(x = ano, y = desvio_pct, group = geo)) +
  geom_hline(yintercept = 0, linetype = "dashed", colour = "grey50", linewidth = 0.4) +
  geom_line(alpha = 0.35, colour = COR_HIST) +
  geom_point(alpha = 0.5, colour = COR_HIST, size = 1.2) +
  facet_wrap(~nivel, scales = "free_y") +
  scale_x_continuous(breaks = seq(ANO_HIST_FIM + 1L, ANO_PROJ_FIM, 2)) +
  labs(title    = "Impacto da Reconciliação nas Projeções",
       subtitle = "Desvio percentual: projeção reconciliada vs. projeção individual",
       x = NULL, y = "Desvio (%)",
       caption  = "Método: benchmarking proporcional top-down (Brasil → Região → Estado).") +
  tema
ggsave("output/graficos/fatores_ajuste.png", g4, width = 12, height = 5, dpi = 150)

# G5: Participação no PIB nacional — todos os estados (2023 vs 2031)
pib_estados_2031 <- proj_rec |>
  filter(ano == ANO_PROJ_FIM, geo_tipo == "estado") |>
  mutate(part_2031 = pib_nominal / sum(pib_nominal, na.rm = TRUE) * 100) |>
  select(geo, part_2031)

pib_estados_2023 <- pib_nom_hist |>
  filter(ano == ANO_HIST_FIM,
         !geo %in% c("Brasil", "Norte", "Nordeste", "Sudeste", "Sul", "Centro-Oeste")) |>
  mutate(part_2023 = pib_nominal / sum(pib_nominal, na.rm = TRUE) * 100) |>
  select(geo, part_2023)

part_comp <- pib_estados_2023 |>
  left_join(pib_estados_2031, by = "geo") |>
  arrange(desc(part_2031)) |>
  mutate(geo = fct_reorder(geo, part_2031))

g5 <- ggplot(part_comp) +
  geom_segment(aes(x = geo, xend = geo, y = part_2023, yend = part_2031),
               colour = "grey65", linewidth = 0.9) +
  geom_point(aes(x = geo, y = part_2023, colour = "2023"), size = 3.0) +
  geom_point(aes(x = geo, y = part_2031, colour = "2031"), size = 3.0) +
  scale_colour_manual(values = c("2023" = COR_HIST, "2031" = COR_PROJ), name = NULL) +
  coord_flip() +
  labs(title    = "Participação no PIB Nacional — Todos os estados (27 UFs)",
       subtitle = "2023 (realizado) vs. 2031 (projetado)",
       x = NULL, y = "% do PIB nacional",
       caption  = "Projeção própria com reconciliação top-down.") +
  tema
ggsave("output/graficos/participacao_pib_estados.png",
       g5, width = 10, height = 9, dpi = 150)

# ==============================================================================
# Parte 6 — Resumo
# ==============================================================================

n_por_geo       <- length(GEO_ORDER)
n_todas_geos    <- 9L + if (!is.null(vab_ativ_rec)) 12L else 0L
n_series_brut   <- if (!is.null(vab_hist)) 9L else 1L
n_por_geo_ativ  <- if (!is.null(vab_ativ_full)) length(GEO_ORDER) else 0L
n_resumo        <- 5L
tem_ativ_aba    <- !is.null(vab_ativ_wide)

message("\n=== Outputs gerados ===")
message("Planilha Excel: output/tabelas/projecoes_pib_estadual.xlsx")
message("  Abas: PIB_nominal | VAB_nominal | Impostos_nominais | Cresc_real_PIB |",
        " Deflator_PIB | VAB_macrossetor",
        if (tem_ativ_aba) " | VAB_atividade" else "",
        " | Intervalos_Confianca | Selecao_Modelos")
message("Gráficos:")
message("  output/graficos/todas_geos/       — ", n_todas_geos,
        " plots (9 macro/agregados + 12 atividades)")
message("  output/graficos/por_geo/          — ", n_por_geo,
        " plots (1 por território, todas variáveis)")
message("  output/graficos/por_geo_atividade/— ", n_por_geo_ativ,
        " plots (stacked area por território)")
message("  output/graficos/series_brutas/    — ", n_series_brut,
        " plots (séries brutas com CI)")
message("  output/graficos/                  — ", n_resumo,
        " plots de resumo")
message("\n05_output.R concluído.")
