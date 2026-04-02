library(tidyverse)
library(forecast)

# Instalar pacotes ausentes
for (p in c("prophet")) {
  if (!requireNamespace(p, quietly = TRUE)) {
    message("Instalando ", p, "...")
    install.packages(p, repos = "https://cloud.r-project.org")
  }
}
library(prophet)

# ==============================================================================
# 03_projecao.R
#
# Modela ~1.089 séries temporais e projeta 2024–2031.
#
# Séries modeladas (todas anuais, 2002/2003–2023):
#   A) Macrossetor × geo (264 séries, atividade = NA):
#        idx_volume e idx_preco de 4 macrossetores × 33 geos
#        Nota: estes índices são DERIVADOS — calculados pela agregação dos
#        val_corrente/val_preco_ant das atividades individuais (não lidos
#        diretamente do IBGE, pois o IBGE não publica índices agregados).
#   B) Impostos × geo (33 séries, atividade = NA):
#        log(impostos_nominal) de 33 geos
#   C) Atividade × geo (~792 séries, atividade preenchida):
#        idx_volume e idx_preco de 12 atividades × 33 geos
#        Fonte: lidos DIRETAMENTE de conta_producao.rds (IBGE)
#        serie_id com prefixo "ativ__" para evitar colisão com macrossetores
#        (ex.: "Roraima|ativ__agropecuaria|idx_volume")
#
# Modelos candidatos (10 por série):
#   rw, arma, arima, sarima, ets, ets_amort, theta, nnar, prophet, ssm
#   Seleção por validação cruzada expanding-window, métrica MASE.
#   Para projeção final: arima/arma sem approximation (mais preciso).
#
# Notas sobre modelos:
#   SARIMA: dados anuais não têm sazonalidade intra-anual; implementado com
#     period=2 para capturar ciclos bienais — auto.arima descarta se não
#     significativo.
#   SSM: StructTS local linear trend (filtro de Kalman via MLE), substitui
#     BSTS (indisponível para R 4.4.2).
#
# Cache: se dados/selecao_modelos.rds existir, o CV é pulado.
#   IMPORTANTE: deletar o cache ao adicionar novas séries (ex.: séries de
#   atividade) para que o CV seja refeito para todas as séries.
#
# Parte 7 — Derivações contábeis (macrossetores):
#   VAB nominal macro  = vab_2023 × cumprod(idx_volume × idx_preco)
#   VAB nominal total  = soma dos macrossetores por geo × ano
#   PIB nominal        = VAB total + impostos (deslogados)
#   Crescimento real   = média ponderada dos idx_volume (pesos = VAB 2023)
#   ATENÇÃO: os filtros de idx_volume/idx_preco usam is.na(atividade) para
#   garantir que apenas séries de macrossetor alimentem a Parte 7 — as
#   séries de atividade têm a mesma variavel mas atividade preenchida.
#
# Parte 7b — Derivações contábeis (atividades individuais):
#   VAB nominal ativ   = vab_2023_ativ × cumprod(idx_volume × idx_preco)
#   IC 95% propagado   = vab_2023_ativ × cumprod(idx_lo95 × idx_prc_lo95)
#
# Entradas:  dados/especiais.rds, dados/conta_producao.rds
# Saídas:    dados/selecao_modelos.rds   (cache CV — uma linha por série)
#            dados/projecoes_brutas.rds  (proj + IC por série × ano)
#            dados/params_modelos.rds    (modelo, parâmetros, MASE, RMSE)
#            dados/vab_macrossetor_proj.rds
#            dados/vab_macro_hist.rds    (histórico macro para gráficos)
#            dados/vab_atividade_hist.rds (histórico atividade para gráficos)
#            dados/vab_atividade_proj.rds (proj + IC por atividade × geo × ano)
#            dados/projecoes_derivadas.rds (PIB, VAB, impostos, deflator)
# ==============================================================================

# ==============================================================================
# Parâmetros globais
# ==============================================================================

H         <- 8L    # horizonte de projeção (2024–2031)
ANO_BASE  <- 2002L
ANO_FIM   <- 2023L
MIN_TRAIN <- 15L   # mínimo de obs para treino no CV → test a partir de 2017

# ==============================================================================
# Mapeamento macrossetores → atividades
# ==============================================================================

MACRO_MAP <- list(
  agropecuaria = "agropecuaria",
  industria    = c("ind_extrativa", "ind_transformacao",
                   "eletricidade_gas_agua", "construcao"),
  adm_publica  = "adm_publica",
  servicos     = c("comercio_veiculos", "transporte_armazenagem",
                   "informacao_comunicacao", "financeiro_seguros",
                   "imobiliaria", "outros_servicos")
)

ativ_macro <- tibble(
  atividade   = unlist(MACRO_MAP),
  macrossetor = rep(names(MACRO_MAP), lengths(MACRO_MAP))
)

# ==============================================================================
# Parte 1 — Preparação dos dados
# ==============================================================================

message("Carregando dados...")
esp <- readRDS("dados/especiais.rds")
cp  <- readRDS("dados/conta_producao.rds")

# Impostos nominais
impostos_df <- esp |>
  filter(variavel == "impostos_nominal") |>
  select(geo, geo_tipo, regiao, ano, valor) |>
  arrange(geo, ano)

# VAB por macrossetor e índices encadeados
# idx_volume_macro = val_preco_ant_macro(t) / val_corrente_macro(t-1)
# idx_preco_macro  = val_corrente_macro(t)  / val_preco_ant_macro(t)
vab_macro <- cp |>
  filter(bloco == "vab", atividade != "total") |>
  inner_join(ativ_macro, by = "atividade") |>
  group_by(geo, geo_tipo, regiao, macrossetor, ano) |>
  summarise(
    val_corrente  = sum(val_corrente,  na.rm = TRUE),
    val_preco_ant = sum(val_preco_ant, na.rm = TRUE),
    .groups = "drop"
  ) |>
  arrange(geo, macrossetor, ano) |>
  group_by(geo, macrossetor) |>
  mutate(
    val_lag    = lag(val_corrente),
    idx_volume = if_else(val_lag > 0 & !is.na(val_preco_ant),
                         val_preco_ant / val_lag, NA_real_),
    idx_preco  = if_else(val_preco_ant > 0 & !is.na(val_preco_ant),
                         val_corrente / val_preco_ant, NA_real_)
  ) |>
  ungroup()

# Salvar série histórica de VAB por macrossetor para uso em outputs/gráficos
saveRDS(
  vab_macro |> select(geo, geo_tipo, regiao, macrossetor, ano,
                      val_corrente, idx_volume, idx_preco),
  "dados/vab_macro_hist.rds"
)

# Lista das 12 atividades individuais a modelar (exclui "total")
ATIVIDADES <- c(
  "agropecuaria", "ind_extrativa", "ind_transformacao",
  "eletricidade_gas_agua", "construcao", "comercio_veiculos",
  "transporte_armazenagem", "informacao_comunicacao",
  "financeiro_seguros", "imobiliaria", "adm_publica", "outros_servicos"
)

# Salvar série histórica de VAB por atividade para outputs/gráficos
saveRDS(
  cp |>
    filter(bloco == "vab", atividade %in% ATIVIDADES) |>
    select(geo, geo_tipo, regiao, atividade, ano,
           val_corrente, idx_volume, idx_preco),
  "dados/vab_atividade_hist.rds"
)

# Montar tibble unificado de séries: idx_volume, idx_preco e log(impostos)
series_idx <- vab_macro |>
  filter(!is.na(idx_volume), !is.na(idx_preco)) |>
  select(geo, geo_tipo, regiao, macrossetor, ano, idx_volume, idx_preco) |>
  pivot_longer(c(idx_volume, idx_preco), names_to = "variavel", values_to = "valor") |>
  filter(!is.na(valor)) |>
  mutate(
    atividade = NA_character_,
    serie_id  = paste(geo, macrossetor, variavel, sep = "|")
  )

series_imp <- impostos_df |>
  mutate(
    macrossetor = "total",
    atividade   = NA_character_,
    variavel    = "log_impostos",
    valor       = log(valor),
    serie_id    = paste(geo, "total", "log_impostos", sep = "|")
  ) |>
  select(geo, geo_tipo, regiao, macrossetor, atividade, ano, variavel, valor, serie_id)

# Séries de atividade individual (12 atividades × 33 geos × 2 variáveis ≈ 792 séries)
# Fonte: índices idx_volume e idx_preco diretos da Conta da Produção (IBGE)
series_ativ <- cp |>
  filter(bloco == "vab", atividade %in% ATIVIDADES,
         !is.na(idx_volume), !is.na(idx_preco)) |>
  select(geo, geo_tipo, regiao, atividade, ano, idx_volume, idx_preco) |>
  pivot_longer(c(idx_volume, idx_preco), names_to = "variavel", values_to = "valor") |>
  filter(!is.na(valor)) |>
  left_join(ativ_macro, by = "atividade") |>   # adiciona coluna macrossetor
  mutate(serie_id = paste(geo, paste0("ativ__", atividade), variavel, sep = "|"))

todas_series <- bind_rows(series_idx, series_imp, series_ativ)
ids <- unique(todas_series$serie_id)
message("Total de séries a modelar: ", length(ids),
        "  (macro: ", nrow(series_idx) / 2L + nrow(series_imp),
        " | atividade: ", nrow(series_ativ) / 2L, ")")

# ==============================================================================
# Parte 2 — Funções dos modelos
# Interface: fn(ts_obj, h) → forecast object com $mean, $lower, $upper
# ==============================================================================

# Wrapper Prophet: converte ts para data frame ds/y, ajusta e retorna forecast
prophet_fc <- function(x, h) {
  anos <- as.integer(time(x))
  df   <- data.frame(ds = as.Date(paste0(anos, "-01-01")), y = as.numeric(x))
  suppressMessages({
    m   <- prophet::prophet(df, yearly.seasonality = FALSE,
                            weekly.seasonality = FALSE, daily.seasonality = FALSE,
                            verbose = FALSE)
    fut <- prophet::make_future_dataframe(m, periods = h, freq = "year")
    pred <- prophet::predict(m, fut)
  })
  proj <- tail(pred, h)
  structure(
    list(
      mean  = ts(proj$yhat,       start = max(anos) + 1L, frequency = 1),
      lower = cbind(proj$yhat_lower, proj$yhat_lower),
      upper = cbind(proj$yhat_upper, proj$yhat_upper)
    ),
    class = "forecast"
  )
}

MODELOS <- list(
  rw        = function(x, h) rwf(x, drift = TRUE, h = h),
  arma      = function(x, h) forecast(auto.arima(x, d = 0,
                              stepwise = TRUE, approximation = TRUE), h = h),
  arima     = function(x, h) forecast(auto.arima(x,
                              stepwise = TRUE, approximation = TRUE), h = h),
  sarima    = function(x, h) forecast(auto.arima(ts(as.numeric(x), frequency = 2),
                              stepwise = TRUE, approximation = TRUE), h = h),
  ets       = function(x, h) forecast(ets(x), h = h),
  ets_amort = function(x, h) forecast(ets(x, damped = TRUE), h = h),
  theta     = function(x, h) thetaf(x, h = h),
  nnar      = function(x, h) forecast(nnetar(x), h = h),
  prophet   = prophet_fc,
  ssm       = function(x, h) forecast(StructTS(x, type = "trend"), h = h)
)

# ==============================================================================
# Parte 3 — Validação cruzada por série (expanding window, h=1)
# ==============================================================================

cv_erros <- function(ts_obj, modelo_fn) {
  n      <- length(ts_obj)
  tempos <- time(ts_obj)
  erros  <- rep(NA_real_, n - MIN_TRAIN)

  for (i in seq(MIN_TRAIN, n - 1L)) {
    treino <- window(ts_obj, end = tempos[i])
    real   <- as.numeric(ts_obj)[i + 1L]
    tryCatch({
      fc   <- modelo_fn(treino, 1L)
      pred <- as.numeric(fc$mean)[1L]
      erros[i - MIN_TRAIN + 1L] <- real - pred
    }, error = function(e) NULL, warning = function(w) NULL)
  }
  erros
}

metricas <- function(erros, ts_obj) {
  vals    <- as.numeric(ts_obj)
  escala  <- mean(abs(diff(vals)), na.rm = TRUE)
  refs    <- tail(vals, length(erros))
  tibble(
    n_ok  = sum(!is.na(erros)),
    rmse  = sqrt(mean(erros^2,  na.rm = TRUE)),
    mae   = mean(abs(erros),    na.rm = TRUE),
    mape  = mean(abs(erros / refs) * 100, na.rm = TRUE),
    mase  = if (escala > 0) mean(abs(erros), na.rm = TRUE) / escala else NA_real_
  )
}

# ==============================================================================
# Parte 4 — Loop de CV com cache
# ==============================================================================

if (file.exists("dados/selecao_modelos.rds")) {
  message("Cache encontrado — pulando CV.")
  selecao_cv <- readRDS("dados/selecao_modelos.rds")
} else {
  message("Iniciando CV: ", length(ids), " séries × ", length(MODELOS), " modelos...")

  resultados_cv <- map_dfr(seq_along(ids), function(i) {
    sid     <- ids[i]
    dados_s <- todas_series |> filter(serie_id == sid) |> arrange(ano)
    ts_obj  <- ts(dados_s$valor, start = min(dados_s$ano), frequency = 1)

    if (i %% 50 == 0 || i == 1)
      message("  [", i, "/", length(ids), "] ", sid)

    map_dfr(names(MODELOS), function(nm) {
      erros <- tryCatch(
        cv_erros(ts_obj, MODELOS[[nm]]),
        error = function(e) rep(NA_real_, length(ts_obj) - MIN_TRAIN)
      )
      metricas(erros, ts_obj) |> mutate(serie_id = sid, modelo = nm)
    })
  })

  # Melhor modelo por série = menor MASE médio
  melhor <- resultados_cv |>
    filter(!is.na(mase)) |>
    group_by(serie_id) |>
    slice_min(mase, n = 1, with_ties = FALSE) |>
    ungroup() |>
    select(serie_id, melhor_modelo = modelo,
           mase_melhor = mase, rmse_melhor = rmse, mae_melhor = mae)

  # Tabela completa: métricas de todos os modelos em colunas
  todas_metricas_wide <- resultados_cv |>
    select(serie_id, modelo, mase) |>
    pivot_wider(names_from = modelo, values_from = mase, names_prefix = "mase_")

  selecao_cv <- melhor |> left_join(todas_metricas_wide, by = "serie_id")

  saveRDS(selecao_cv, "dados/selecao_modelos.rds")
  message("CV concluído.")
}

# ==============================================================================
# Parte 5 — Resumo da seleção
# ==============================================================================

message("\n--- Modelos vencedores ---")
print(sort(table(selecao_cv$melhor_modelo), decreasing = TRUE))

# ==============================================================================
# Parte 6 — Projeção final (2024–2031) com o melhor modelo por série
# ==============================================================================

# Para projeção final: ARIMA/ARMA sem approximation (mais preciso)
MODELOS_FINAL <- MODELOS
MODELOS_FINAL$arima <- function(x, h) forecast(auto.arima(x,
                                  stepwise = FALSE, approximation = FALSE), h = h)
MODELOS_FINAL$arma  <- function(x, h) forecast(auto.arima(x, d = 0,
                                  stepwise = FALSE, approximation = FALSE), h = h)

message("\nGerando projeções finais...")

projecoes_brutas <- map_dfr(ids, function(sid) {
  dados_s   <- todas_series |> filter(serie_id == sid) |> arrange(ano)
  ts_obj    <- ts(dados_s$valor, start = min(dados_s$ano), frequency = 1)
  modelo_nm <- selecao_cv |> filter(serie_id == sid) |> pull(melhor_modelo)

  if (length(modelo_nm) == 0 || is.na(modelo_nm)) modelo_nm <- "arima"

  fc <- tryCatch(
    MODELOS_FINAL[[modelo_nm]](ts_obj, H),
    error = function(e) {
      message("  Fallback ARIMA para: ", sid)
      modelo_nm <<- "arima"
      MODELOS_FINAL$arima(ts_obj, H)
    }
  )

  parametros_str <- tryCatch(
    if (!is.null(fc$method)) as.character(fc$method) else toupper(modelo_nm),
    error = function(e) modelo_nm
  )

  meta <- dados_s |>
    distinct(geo, geo_tipo, regiao, macrossetor, atividade, variavel) |>
    slice(1)

  tibble(
    geo         = meta$geo,
    geo_tipo    = meta$geo_tipo,
    regiao      = meta$regiao,
    macrossetor = meta$macrossetor,
    atividade   = meta$atividade,
    variavel    = meta$variavel,
    serie_id    = sid,
    modelo      = modelo_nm,
    parametros  = parametros_str,
    ano         = seq(ANO_FIM + 1L, ANO_FIM + H),
    proj        = as.numeric(fc$mean),
    lo80        = if (!is.null(fc$lower)) as.numeric(fc$lower[, 1]) else NA_real_,
    hi80        = if (!is.null(fc$upper)) as.numeric(fc$upper[, 1]) else NA_real_,
    lo95        = if (!is.null(fc$lower) && ncol(fc$lower) > 1)
                    as.numeric(fc$lower[, 2]) else NA_real_,
    hi95        = if (!is.null(fc$upper) && ncol(fc$upper) > 1)
                    as.numeric(fc$upper[, 2]) else NA_real_
  )
})

saveRDS(projecoes_brutas, "dados/projecoes_brutas.rds")
message("Projeções brutas: ", nrow(projecoes_brutas), " linhas")

# Tabela de parâmetros: uma linha por série com modelo selecionado e parâmetros
params_modelos <- projecoes_brutas |>
  distinct(serie_id, geo, geo_tipo, regiao, macrossetor, atividade, variavel,
           modelo, parametros) |>
  left_join(
    selecao_cv |> select(serie_id, mase_melhor, rmse_melhor, mae_melhor),
    by = "serie_id"
  )
saveRDS(params_modelos, "dados/params_modelos.rds")
message("Params modelos: ", nrow(params_modelos), " séries")

# ==============================================================================
# Parte 7 — Derivações contábeis
# ==============================================================================

message("Calculando variáveis derivadas...")

# Ponto de partida: VAB corrente e impostos em 2023
base_2023 <- vab_macro |>
  filter(ano == ANO_FIM) |>
  select(geo, macrossetor, vab_2023 = val_corrente)

imp_2023 <- impostos_df |>
  filter(ano == ANO_FIM) |>
  select(geo, imp_2023 = valor)

# Índices projetados por macrossetor (excluir séries de atividade)
proj_vol <- projecoes_brutas |>
  filter(variavel == "idx_volume", is.na(atividade)) |>
  select(geo, macrossetor, ano, idx_volume = proj,
         idx_vol_lo95 = lo95, idx_vol_hi95 = hi95)

proj_prc <- projecoes_brutas |>
  filter(variavel == "idx_preco", is.na(atividade)) |>
  select(geo, macrossetor, ano, idx_preco = proj,
         idx_prc_lo95 = lo95, idx_prc_hi95 = hi95)

# VAB nominal por macrossetor projetado
vab_proj <- proj_vol |>
  inner_join(proj_prc, by = c("geo", "macrossetor", "ano")) |>
  left_join(base_2023, by = c("geo", "macrossetor")) |>
  arrange(geo, macrossetor, ano) |>
  group_by(geo, macrossetor) |>
  mutate(
    fator_acum       = cumprod(idx_volume * idx_preco),
    vab_nominal      = vab_2023 * fator_acum,
    crescimento_real = idx_volume - 1
  ) |>
  ungroup()

saveRDS(vab_proj, "dados/vab_macrossetor_proj.rds")

# VAB total por geo × ano
vab_total_proj <- vab_proj |>
  group_by(geo, ano) |>
  summarise(vab_nominal_total = sum(vab_nominal, na.rm = TRUE), .groups = "drop")

# Impostos projetados (deslogar)
imp_proj <- projecoes_brutas |>
  filter(variavel == "log_impostos") |>
  transmute(geo, ano,
            impostos_nominal = exp(proj),
            imp_lo95         = exp(lo95),
            imp_hi95         = exp(hi95))

# PIB nominal projetado = VAB total + impostos
pib_proj <- vab_total_proj |>
  left_join(imp_proj, by = c("geo", "ano")) |>
  mutate(pib_nominal = vab_nominal_total + impostos_nominal)

# Crescimento real do PIB: média ponderada dos crescimentos dos macrossetores
# pesos = participação no VAB em 2023
pesos_2023 <- base_2023 |>
  group_by(geo) |>
  mutate(peso = vab_2023 / sum(vab_2023, na.rm = TRUE)) |>
  ungroup()

cresc_real_pib <- vab_proj |>
  left_join(pesos_2023 |> select(geo, macrossetor, peso), by = c("geo", "macrossetor")) |>
  group_by(geo, ano) |>
  summarise(tx_cresc_pib_real = sum(crescimento_real * peso, na.rm = TRUE),
            .groups = "drop")

# Deflator do PIB projetado
# deflator(t) = variação do PIB nominal(t/2023) / variação do volume(t/2023)
pib_2023 <- esp |>
  filter(variavel == "pib_nominal", ano == ANO_FIM) |>
  select(geo, pib_2023 = valor)

vol_pib_proj <- cresc_real_pib |>
  arrange(geo, ano) |>
  group_by(geo) |>
  mutate(vol_idx_base2023 = cumprod(1 + tx_cresc_pib_real)) |>
  ungroup()

projecoes_derivadas <- pib_proj |>
  left_join(cresc_real_pib, by = c("geo", "ano")) |>
  left_join(vol_pib_proj |> select(geo, ano, vol_idx_base2023), by = c("geo", "ano")) |>
  left_join(pib_2023, by = "geo") |>
  mutate(
    deflator_pib = if_else(
      vol_idx_base2023 > 0,
      (pib_nominal / pib_2023) / vol_idx_base2023,
      NA_real_
    )
  ) |>
  left_join(
    esp |> filter(ano == ANO_FIM) |>
      distinct(geo, geo_tipo, regiao),
    by = "geo"
  ) |>
  select(geo, geo_tipo, regiao, ano,
         pib_nominal, vab_nominal_total, impostos_nominal,
         tx_cresc_pib_real, deflator_pib)

saveRDS(projecoes_derivadas, "dados/projecoes_derivadas.rds")

# ==============================================================================
# Parte 7b — VAB nominal por atividade individual
# ==============================================================================
# Fonte: idx_volume e idx_preco diretamente da Conta da Produção (IBGE),
# modelados individualmente por atividade × geo no loop de CV acima.

message("Calculando VAB nominal por atividade...")

# Base 2023: VAB a preço corrente por atividade × geo
base_2023_ativ <- cp |>
  filter(bloco == "vab", atividade %in% ATIVIDADES, ano == ANO_FIM) |>
  select(geo, atividade, vab_2023_ativ = val_corrente)

# Índices projetados: filtrar séries de atividade (!is.na(atividade))
proj_vol_ativ <- projecoes_brutas |>
  filter(variavel == "idx_volume", !is.na(atividade)) |>
  select(geo, atividade, macrossetor, ano,
         idx_volume   = proj,
         idx_vol_lo95 = lo95,
         idx_vol_hi95 = hi95)

proj_prc_ativ <- projecoes_brutas |>
  filter(variavel == "idx_preco", !is.na(atividade)) |>
  select(geo, atividade, macrossetor, ano,
         idx_preco    = proj,
         idx_prc_lo95 = lo95,
         idx_prc_hi95 = hi95)

# VAB nominal = val_corrente_2023 × cumprod(idx_volume × idx_preco)
vab_ativ_proj <- proj_vol_ativ |>
  inner_join(proj_prc_ativ, by = c("geo", "atividade", "macrossetor", "ano")) |>
  left_join(base_2023_ativ,  by = c("geo", "atividade")) |>
  arrange(geo, atividade, ano) |>
  group_by(geo, atividade) |>
  mutate(
    fator_acum  = cumprod(idx_volume * idx_preco),
    vab_nominal = vab_2023_ativ * fator_acum,
    flo         = cumprod(coalesce(idx_vol_lo95, idx_volume) *
                          coalesce(idx_prc_lo95, idx_preco)),
    fhi         = cumprod(coalesce(idx_vol_hi95, idx_volume) *
                          coalesce(idx_prc_hi95, idx_preco)),
    vab_lo95    = vab_2023_ativ * flo,
    vab_hi95    = vab_2023_ativ * fhi
  ) |>
  ungroup() |>
  select(geo, atividade, macrossetor, ano, vab_nominal, vab_lo95, vab_hi95)

saveRDS(vab_ativ_proj, "dados/vab_atividade_proj.rds")
message("VAB por atividade projetado: ", nrow(vab_ativ_proj), " linhas")

# ==============================================================================
# Parte 8 — Verificações finais
# ==============================================================================

message("\n--- Verificações finais ---")
message("projecoes_brutas:     ", nrow(projecoes_brutas),
        " linhas (esperado: ", length(ids) * H, ")")
message("projecoes_derivadas:  ", nrow(projecoes_derivadas), " linhas")
message("vab_macrossetor_proj: ", nrow(vab_proj), " linhas")
message("vab_atividade_proj:   ", nrow(vab_ativ_proj), " linhas")

# Identidade PIB = VAB + Impostos nas projeções
check <- projecoes_derivadas |>
  mutate(
    pib_recalc = vab_nominal_total + impostos_nominal,
    desvio_rel = (pib_nominal - pib_recalc) / pib_nominal * 100
  )
message("Identidade PIB=VAB+Impostos: desvio max = ",
        round(max(abs(check$desvio_rel), na.rm = TRUE), 6), "%")

# Amostra: Brasil e Roraima
message("\n--- PIB nominal projetado (R$ milhões) — Brasil e Roraima ---")
projecoes_derivadas |>
  filter(geo %in% c("Brasil", "Roraima")) |>
  select(geo, ano, pib_nominal, tx_cresc_pib_real, deflator_pib) |>
  mutate(across(c(pib_nominal), ~ round(.x / 1e6, 3)),  # trilhões
         across(c(tx_cresc_pib_real, deflator_pib), ~ round(.x * 100, 2))) |>
  rename(`PIB (tri R$)` = pib_nominal,
         `Cresc real (%)` = tx_cresc_pib_real,
         `Deflator (%)` = deflator_pib) |>
  print(n = 20)

message("\n03_projecao.R concluído.")
