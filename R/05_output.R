library(tidyverse)

if (!requireNamespace("openxlsx", quietly = TRUE))
  install.packages("openxlsx", repos = "https://cloud.r-project.org")
library(openxlsx)

# ==============================================================================
# 05_output.R
#
# Gera tabelas Excel e gráficos a partir das projeções reconciliadas.
#
# Entradas:  dados/especiais.rds
#            dados/projecoes_reconciliadas.rds
#            dados/vab_macro_reconciliado.rds
#
# Saídas:
#   output/tabelas/projecoes_pib_estadual.xlsx
#     Abas: PIB_nominal | VAB_nominal | Impostos_nominais |
#           Cresc_real_PIB | Deflator_PIB | VAB_macrossetor
#   output/graficos/
#     pib_nominal_brasil.png
#     cresc_real_regioes.png
#     pib_nominal_roraima.png
#     fatores_ajuste.png
#     participacao_pib_estados.png
# ==============================================================================

# ==============================================================================
# Parte 0 — Parâmetros
# ==============================================================================

ANO_HIST_INI <- 2002L
ANO_HIST_FIM <- 2023L
ANO_PROJ_FIM <- 2031L

# Ordem IBGE das unidades geográficas (usada como colunas nas tabelas)
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

# Geos que são totalizadores (regiões + Brasil) — formatação diferenciada no Excel
GEO_AGREGADO <- c("Brasil", "Norte", "Nordeste", "Sudeste", "Sul", "Centro-Oeste")

dir.create("output/tabelas",  showWarnings = FALSE, recursive = TRUE)
dir.create("output/graficos", showWarnings = FALSE, recursive = TRUE)

# ==============================================================================
# Parte 1 — Carregar dados
# ==============================================================================

message("Carregando dados...")
esp      <- readRDS("dados/especiais.rds")
proj_rec <- readRDS("dados/projecoes_reconciliadas.rds")
vab_mac  <- readRDS("dados/vab_macro_reconciliado.rds")

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

# Taxa de crescimento real histórica: (vol_t / vol_{t-1}) - 1
hist_cresc <- pib_vol_hist |>
  arrange(geo, ano) |>
  group_by(geo) |>
  mutate(tx_cresc_pib_real = vol_enc / lag(vol_enc) - 1) |>
  ungroup() |>
  filter(!is.na(tx_cresc_pib_real)) |>
  select(geo, ano, tx_cresc_pib_real)

# Deflator histórico (yoy): (1 + nom_growth) / (1 + real_growth) - 1
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

# Deflator projetado (yoy): (1 + nom_growth) / (1 + real_growth) - 1
# Para 2024 (primeiro ano projetado), o denominador é o PIB nominal de 2023
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
    pib_lag   = coalesce(pib_lag_proj, pib_lag_base),
    g_nom     = pib_nominal / pib_lag - 1,
    deflator_pib = (1 + g_nom) / (1 + tx_cresc_pib_real) - 1
  ) |>
  select(geo, ano, deflator_pib)

# ==============================================================================
# Parte 3 — Montar séries combinadas e pivotar para wide (ano × geo)
# ==============================================================================

# Converte para wide com geos em colunas na ordem IBGE
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
) |>
  to_wide("pib_nominal")

vab_wide <- bind_rows(
  vab_nom_hist |> filter(ano >= ANO_HIST_INI),
  proj_rec     |> select(geo, ano, vab_nominal = vab_nominal_total)
) |>
  to_wide("vab_nominal")

imp_wide <- bind_rows(
  imp_nom_hist |> filter(ano >= ANO_HIST_INI),
  proj_rec     |> select(geo, ano, impostos_nominal)
) |>
  to_wide("impostos_nominal")

cresc_wide <- bind_rows(
  hist_cresc |> filter(ano > ANO_HIST_INI),      # 2003 em diante (requer lag)
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

# VAB por macrossetor (projetado): macrossetor × ano × geo
vab_macro_wide <- vab_mac |>
  filter(geo %in% GEO_ORDER) |>
  mutate(geo = factor(geo, levels = GEO_ORDER)) |>
  select(macrossetor, ano, geo, vab_nominal) |>
  mutate(vab_nominal = round(vab_nominal, 0)) |>
  arrange(macrossetor, ano, geo) |>
  pivot_wider(names_from = geo, values_from = vab_nominal)

# ==============================================================================
# Parte 4 — Exportar planilha Excel
# ==============================================================================

message("Gerando planilha Excel...")

# ----- Estilos ---------------------------------------------------------------
st_header  <- createStyle(fontSize = 11, fontColour = "#FFFFFF",
                           fgFill = "#1F497D", halign = "center",
                           textDecoration = "bold")
st_titulo  <- createStyle(fontSize = 12, fontColour = "#1F497D",
                           textDecoration = "bold", halign = "left")
st_ano     <- createStyle(halign = "center", textDecoration = "bold")
st_num     <- createStyle(numFmt = "#,##0.00", halign = "right")
st_pct     <- createStyle(numFmt = "0.00",    halign = "right")
st_sep     <- createStyle(border = "Bottom",  borderColour = "#C0392B",
                           borderStyle = "medium")

# ----- Função utilitária para escrever cada aba ------------------------------
# df deve ter coluna 'ano' (sem renomear antes de chamar)
escrever_aba <- function(wb, nome_aba, df, fmt = "num", titulo = NULL) {
  addWorksheet(wb, nome_aba)

  linha_dados <- 1L

  # Linha de título (opcional)
  if (!is.null(titulo)) {
    writeData(wb, nome_aba, titulo, startRow = 1, startCol = 1)
    mergeCells(wb, nome_aba, rows = 1, cols = 1:ncol(df))
    addStyle(wb, nome_aba, st_titulo, rows = 1, cols = 1, stack = FALSE)
    linha_dados <- 2L
  }

  # Cabeçalho e dados
  df_out <- rename(df, Ano = ano)
  writeData(wb, nome_aba, df_out, startRow = linha_dados)

  # Estilo cabeçalho
  addStyle(wb, nome_aba, st_header,
           rows = linha_dados, cols = 1:ncol(df_out), gridExpand = TRUE)

  # Estilo coluna Ano
  addStyle(wb, nome_aba, st_ano,
           rows = (linha_dados + 1):(linha_dados + nrow(df_out)),
           cols = 1, gridExpand = TRUE)

  # Estilo valores
  st_val <- if (fmt == "pct") st_pct else st_num
  addStyle(wb, nome_aba, st_val,
           rows = (linha_dados + 1):(linha_dados + nrow(df_out)),
           cols = 2:ncol(df_out), gridExpand = TRUE)

  # Linha separadora histórico/projetado (vermelho)
  n_hist <- sum(df$ano <= ANO_HIST_FIM)
  if (n_hist > 0 && n_hist < nrow(df)) {
    addStyle(wb, nome_aba, st_sep,
             rows = linha_dados + n_hist,
             cols = 1:ncol(df_out),
             gridExpand = TRUE, stack = TRUE)
  }

  # Freeze e larguras
  freezePane(wb, nome_aba, firstActiveRow = linha_dados + 1L, firstActiveCol = 2L)
  setColWidths(wb, nome_aba, cols = 1,          widths = 6)
  setColWidths(wb, nome_aba, cols = 2:ncol(df_out), widths = 14)

  invisible(wb)
}

# ----- Criar workbook --------------------------------------------------------
wb <- createWorkbook()

wb <- escrever_aba(wb, "PIB_nominal", pib_wide,
                   titulo = "PIB nominal — R$ milhões (correntes)")

wb <- escrever_aba(wb, "VAB_nominal", vab_wide,
                   titulo = "VAB nominal — R$ milhões (correntes)")

wb <- escrever_aba(wb, "Impostos_nominais", imp_wide,
                   titulo = "Impostos líquidos de subsídios — R$ milhões (correntes)")

wb <- escrever_aba(wb, "Cresc_real_PIB", cresc_wide,
                   fmt   = "pct",
                   titulo = "Taxa de crescimento real do PIB — % a.a.")

wb <- escrever_aba(wb, "Deflator_PIB", deflator_wide,
                   fmt   = "pct",
                   titulo = "Deflator implícito do PIB — % a.a.")

# Aba VAB macrossetor (estrutura diferente: macrossetor + ano como linhas)
addWorksheet(wb, "VAB_macrossetor")
writeData(wb, "VAB_macrossetor",
          "VAB por macrossetor — R$ milhões (projetado 2024–2031)",
          startRow = 1, startCol = 1)
mergeCells(wb, "VAB_macrossetor", rows = 1, cols = 1:ncol(vab_macro_wide))
addStyle(wb, "VAB_macrossetor", st_titulo, rows = 1, cols = 1)
writeData(wb, "VAB_macrossetor", vab_macro_wide, startRow = 2)
addStyle(wb, "VAB_macrossetor", st_header,
         rows = 2, cols = 1:ncol(vab_macro_wide), gridExpand = TRUE)
addStyle(wb, "VAB_macrossetor", st_num,
         rows = 3:(2 + nrow(vab_macro_wide)),
         cols = 3:ncol(vab_macro_wide), gridExpand = TRUE)
freezePane(wb, "VAB_macrossetor", firstActiveRow = 3L, firstActiveCol = 3L)
setColWidths(wb, "VAB_macrossetor", cols = 1:2, widths = 16)
setColWidths(wb, "VAB_macrossetor", cols = 3:ncol(vab_macro_wide), widths = 14)

saveWorkbook(wb, "output/tabelas/projecoes_pib_estadual.xlsx", overwrite = TRUE)
message("Salvo: output/tabelas/projecoes_pib_estadual.xlsx")

# ==============================================================================
# Parte 5 — Gráficos
# ==============================================================================

message("Gerando gráficos...")

tema <- theme_minimal(base_size = 12) +
  theme(
    plot.title       = element_text(face = "bold", size = 13),
    plot.subtitle    = element_text(colour = "grey40", size = 10),
    plot.caption     = element_text(colour = "grey55", size = 8),
    panel.grid.minor = element_blank(),
    legend.position  = "bottom"
  )

COR_HIST <- "#1F497D"
COR_PROJ <- "#C0392B"

# ---- G1: PIB nominal Brasil (histórico + projetado) -------------------------
pib_brasil_ts <- bind_rows(
  pib_nom_hist |>
    filter(geo == "Brasil", ano >= ANO_HIST_INI) |>
    mutate(tipo = "Histórico"),
  proj_rec |>
    filter(geo == "Brasil") |>
    select(geo, ano, pib_nominal) |>
    mutate(tipo = "Projetado")
)

g1 <- ggplot(pib_brasil_ts,
             aes(x = ano, y = pib_nominal / 1e6, colour = tipo)) +
  geom_vline(xintercept = ANO_HIST_FIM + 0.5,
             linetype = "dashed", colour = "grey60", linewidth = 0.6) +
  geom_line(linewidth = 1.1) +
  geom_point(size = 2.2) +
  scale_colour_manual(values = c(Histórico = COR_HIST, Projetado = COR_PROJ),
                      name = NULL) +
  scale_x_continuous(breaks = seq(ANO_HIST_INI, ANO_PROJ_FIM, 2)) +
  scale_y_continuous(labels = scales::label_number(suffix = " tri", accuracy = 0.1)) +
  labs(title    = "PIB Nominal — Brasil",
       subtitle = "R$ trilhões (valores correntes)",
       x = NULL, y = NULL,
       caption  = "Fonte: IBGE (histórico 2002–2023); projeção própria (2024–2031).") +
  tema

ggsave("output/graficos/pib_nominal_brasil.png", g1,
       width = 10, height = 6, dpi = 150)

# ---- G2: Crescimento real por região (barras, período projetado) ------------
REGIOES_BR <- c("Brasil", "Norte", "Nordeste", "Sudeste", "Sul", "Centro-Oeste")

cresc_regioes <- proj_rec |>
  filter(geo %in% REGIOES_BR) |>
  mutate(
    geo = factor(geo, levels = REGIOES_BR),
    tx  = tx_cresc_pib_real * 100
  ) |>
  select(geo, ano, tx)

g2 <- ggplot(cresc_regioes, aes(x = ano, y = tx, fill = geo)) +
  geom_col(position = position_dodge(0.8), width = 0.75) +
  geom_hline(yintercept = 0, colour = "black", linewidth = 0.3) +
  scale_fill_brewer(palette = "Set2", name = NULL) +
  scale_x_continuous(breaks = seq(ANO_HIST_FIM + 1L, ANO_PROJ_FIM)) +
  labs(title    = "Taxa de Crescimento Real do PIB — Brasil e Regiões",
       subtitle = "Projeção 2024–2031 (% a.a.)",
       x = NULL, y = "% a.a.",
       caption  = "Projeção própria com reconciliação top-down.") +
  tema

ggsave("output/graficos/cresc_real_regioes.png", g2,
       width = 12, height = 6, dpi = 150)

# ---- G3: PIB nominal Roraima ------------------------------------------------
pib_rr_ts <- bind_rows(
  pib_nom_hist |>
    filter(geo == "Roraima", ano >= ANO_HIST_INI) |>
    mutate(tipo = "Histórico"),
  proj_rec |>
    filter(geo == "Roraima") |>
    select(geo, ano, pib_nominal) |>
    mutate(tipo = "Projetado")
)

g3 <- ggplot(pib_rr_ts,
             aes(x = ano, y = pib_nominal / 1e3, colour = tipo)) +
  geom_vline(xintercept = ANO_HIST_FIM + 0.5,
             linetype = "dashed", colour = "grey60", linewidth = 0.6) +
  geom_line(linewidth = 1.1) +
  geom_point(size = 2.2) +
  scale_colour_manual(values = c(Histórico = COR_HIST, Projetado = COR_PROJ),
                      name = NULL) +
  scale_x_continuous(breaks = seq(ANO_HIST_INI, ANO_PROJ_FIM, 2)) +
  scale_y_continuous(labels = scales::label_number(suffix = " bi", accuracy = 0.1)) +
  labs(title    = "PIB Nominal — Roraima",
       subtitle = "R$ bilhões (valores correntes)",
       x = NULL, y = NULL,
       caption  = "Fonte: IBGE (histórico 2002–2023); projeção própria (2024–2031).") +
  tema

ggsave("output/graficos/pib_nominal_roraima.png", g3,
       width = 10, height = 6, dpi = 150)

# ---- G4: Fatores de ajuste da reconciliação (desvio em %) ------------------
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

ggsave("output/graficos/fatores_ajuste.png", g4,
       width = 12, height = 5, dpi = 150)

# ---- G5: Participação no PIB nacional — top 15 estados (2023 vs 2031) ------
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
  slice_head(n = 15) |>
  mutate(geo = fct_reorder(geo, part_2031))

g5 <- ggplot(part_comp) +
  geom_segment(aes(x = geo, xend = geo, y = part_2023, yend = part_2031),
               colour = "grey65", linewidth = 0.9) +
  geom_point(aes(x = geo, y = part_2023, colour = "2023"), size = 3.5) +
  geom_point(aes(x = geo, y = part_2031, colour = "2031"), size = 3.5) +
  scale_colour_manual(values = c("2023" = COR_HIST, "2031" = COR_PROJ),
                      name = NULL) +
  coord_flip() +
  labs(title    = "Participação no PIB Nacional — Top 15 estados",
       subtitle = "2023 (realizado) vs. 2031 (projetado)",
       x = NULL, y = "% do PIB nacional",
       caption  = "Projeção própria com reconciliação top-down.") +
  tema

ggsave("output/graficos/participacao_pib_estados.png", g5,
       width = 10, height = 7, dpi = 150)

# ==============================================================================
# Parte 6 — Resumo
# ==============================================================================

message("\n=== Outputs gerados ===")
message("Planilha Excel:")
message("  output/tabelas/projecoes_pib_estadual.xlsx")
message("  Abas: PIB_nominal | VAB_nominal | Impostos_nominais |",
        " Cresc_real_PIB | Deflator_PIB | VAB_macrossetor")
message("Gráficos (output/graficos/):")
for (f in c("pib_nominal_brasil.png", "cresc_real_regioes.png",
            "pib_nominal_roraima.png", "fatores_ajuste.png",
            "participacao_pib_estados.png")) {
  message("  ", f)
}
message("\n05_output.R concluído.")
