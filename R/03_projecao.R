source("R/config.R", local = FALSE)
source("R/utils_cache.R", local = FALSE)
source("R/utils_logging.R", local = FALSE)

library(tidyverse)
library(forecast)

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
# Família de modelos (7 por série):
#   rw, arma, arima, ets, ets_amort, theta, ssm
#   Excluídos do baseline: sarima (period=2 sem respaldo em dados anuais),
#   nnar (instável com ~22 obs), prophet (superdimensionado para anuais).
#
# Seleção — CV two-stage expanding-window, horizontes h=1/2/3:
#   Stage 1 (triagem rápida, approx=TRUE): todos os 7 modelos → top N_FINALISTAS
#   Stage 2 (avaliação precisa, approx=FALSE): apenas os finalistas; modelos
#     não-ARIMA reutilizam resultado do stage 1. Vencedor = menor MASE ponderado.
#   Métrica: MASE ponderado (pesos PESOS_CV = 0.5/0.3/0.2 para h=1/2/3).
#   Para projeção final: arima/arma com stepwise=FALSE, approximation=FALSE,
#     max.p/q=3, max.P/Q/D=0 — mesma especificação do stage 2.
#
# Cache: a seleção usa metadata com hashes dos insumos, parâmetros e do script.
#   O cache só é reutilizado quando a assinatura continua válida.
#   Schema atual: CACHE_SCHEMA_VERSION = "bloco4_v1" (config.R).
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
# Saídas:    dados/selecao_modelos.rds      (cache CV two-stage — uma linha por série)
#            dados/selecao_modelos_meta.rds (metadata de invalidação do cache)
#            dados/metricas_cv_detalhadas.rds (métricas por série × modelo × horizonte)
#            dados/projecoes_brutas.rds     (proj + IC por série × ano)
#            dados/params_modelos.rds       (modelo, parâmetros, mase_ponderado,
#                                            mase_venc_h1/h2/h3 por série)
#            dados/fallback_log.rds         (séries com fallback para ARIMA)
#            dados/vab_macrossetor_proj.rds
#            dados/vab_macro_hist.rds       (histórico macro para gráficos)
#            dados/vab_atividade_hist.rds   (histórico atividade para gráficos)
#            dados/vab_atividade_proj.rds   (proj + IC por atividade × geo × ano)
#            dados/projecoes_derivadas.rds  (PIB, VAB, impostos, deflator)
# ==============================================================================

# ==============================================================================
# Parâmetros globais
# ==============================================================================


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

fallback_log <- tibble(
  serie_id        = character(),
  modelo_original = character(),
  modelo_fallback = character(),
  etapa           = character(),
  motivo          = character()
)

if (!exists("LOG_EXECUCAO_ID", envir = .GlobalEnv, inherits = FALSE)) {
  inicializar_log_execucao(
    prefixo = "03_projecao",
    contexto = list(
      branch = obter_git_branch(),
      commit = obter_git_commit(),
      seed = SEED_GLOBAL,
      r_version = R.version.string
    )
  )
}

registrar_evento_log("03_projecao", "INFO", "Carregando dados de projeção")

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

# Família principal de modelos — 7 candidatos para séries anuais curtas.
# Removidos do baseline: sarima (period=2 artificial), nnar (instável com ~22 obs),
# prophet (superdimensionado para anuais sem sazonalidade).
MODELOS <- list(
  rw        = function(x, h) rwf(x, drift = TRUE, h = h),
  arma      = function(x, h) forecast(auto.arima(x, d = 0,
                              stepwise = TRUE, approximation = TRUE), h = h),
  arima     = function(x, h) forecast(auto.arima(x,
                              stepwise = TRUE, approximation = TRUE), h = h),
  ets       = function(x, h) forecast(ets(x), h = h),
  ets_amort = function(x, h) forecast(ets(x, damped = TRUE), h = h),
  theta     = function(x, h) thetaf(x, h = h),
  ssm       = function(x, h) forecast(StructTS(x, type = "trend"), h = h)
)

executar_modelo_com_log <- function(expr, etapa, serie_id, modelo) {
  avisos <- character()

  resultado <- tryCatch(
    withCallingHandlers(
      expr,
      warning = function(w) {
        avisos <<- c(avisos, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    ),
    error = function(e) {
      registrar_evento_log(
        etapa = "03_projecao",
        nivel = "ERROR",
        mensagem = paste("Erro em", etapa),
        detalhe = paste("serie_id =", serie_id, "| modelo =", modelo, "|", conditionMessage(e))
      )
      structure(list(mensagem = conditionMessage(e)), class = "erro_modelo")
    }
  )

  if (length(avisos) > 0) {
    registrar_evento_log(
      etapa = "03_projecao",
      nivel = "WARNING",
      mensagem = paste("Warning em", etapa),
      detalhe = paste("serie_id =", serie_id, "| modelo =", modelo, "|", paste(unique(avisos), collapse = " || "))
    )
  }

  resultado
}

# ==============================================================================
# Parte 3 — Validação cruzada por série (expanding window, h=1)
# ==============================================================================

# CV expanding window com múltiplos horizontes.
# Retorna matriz de erros: linhas = janelas de treino, colunas = horizontes.
# Usa h_max = max(horizontes) por previsão para eficiência (um único ajuste
# do modelo por janela cobre todos os horizontes solicitados).
cv_erros_multi <- function(ts_obj, modelo_fn, serie_id, modelo, horizontes) {
  h_max  <- max(horizontes)
  n      <- length(ts_obj)
  tempos <- time(ts_obj)
  # Janelas válidas: treino em MIN_TRAIN..n-h_max para ter h_max obs de hold-out
  n_win  <- n - MIN_TRAIN - h_max + 1L
  if (n_win <= 0L) return(matrix(NA_real_, nrow = 0L, ncol = length(horizontes),
                                 dimnames = list(NULL, paste0("h", horizontes))))
  erros <- matrix(NA_real_, nrow = n_win, ncol = length(horizontes))
  colnames(erros) <- paste0("h", horizontes)

  for (i in seq(MIN_TRAIN, n - h_max)) {
    treino <- window(ts_obj, end = tempos[i])
    fc     <- executar_modelo_com_log(
      modelo_fn(treino, h_max),
      etapa    = "cv",
      serie_id = serie_id,
      modelo   = modelo
    )
    if (!inherits(fc, "erro_modelo")) {
      preds <- as.numeric(fc$mean)
      reais <- as.numeric(ts_obj)[i + seq_len(h_max)]
      for (j in seq_along(horizontes))
        erros[i - MIN_TRAIN + 1L, j] <- reais[horizontes[j]] - preds[horizontes[j]]
    }
  }
  erros
}

# Calcula métricas por horizonte a partir da matriz de erros e retorna tibble
# com uma linha por horizonte + coluna mase_ponderado (agregado com pesos).
metricas_multi <- function(erros_mat, ts_obj, horizontes, pesos) {
  vals    <- as.numeric(ts_obj)
  escala  <- mean(abs(diff(vals)), na.rm = TRUE)
  pesos_n <- pesos / sum(pesos)

  metr_h <- map_dfr(seq_along(horizontes), function(j) {
    e <- erros_mat[, j]
    tibble(
      horizonte = horizontes[j],
      n_ok      = sum(!is.na(e)),
      rmse      = sqrt(mean(e^2, na.rm = TRUE)),
      mae       = mean(abs(e),   na.rm = TRUE),
      mase      = if (escala > 0) mean(abs(e), na.rm = TRUE) / escala else NA_real_
    )
  })

  mase_pond <- if (all(is.na(metr_h$mase))) NA_real_ else
    sum(metr_h$mase * pesos_n, na.rm = TRUE)

  metr_h |> mutate(mase_ponderado = mase_pond)
}

metadata_cache_cv <- criar_metadata_cache(
  nome = "selecao_modelos",
  objetos = list(
    todas_series = todas_series,
    ids = ids,
    atividades = ATIVIDADES,
    macro_map = MACRO_MAP
  ),
  arquivos = list(
    especiais = "dados/especiais.rds",
    conta_producao = "dados/conta_producao.rds"
  ),
  parametros = list(
    H = H,
    ANO_BASE = ANO_BASE,
    ANO_FIM = ANO_FIM,
    MIN_TRAIN = MIN_TRAIN,
    modelos = names(MODELOS),
    horizontes_cv = HORIZONTES_CV,
    pesos_cv = PESOS_CV,
    n_finalistas = N_FINALISTAS,
    cache_schema_version = CACHE_SCHEMA_VERSION
  ),
  script_path = "R/03_projecao.R"
)

# ==============================================================================
# Parte 4 — Loop de CV com cache
# ==============================================================================

cache_reutilizado <- cache_valido(
  CACHE_MODELOS_PATH,
  CACHE_MODELOS_META_PATH,
  metadata_cache_cv
)

if (cache_reutilizado) {
  message("Cache valido encontrado — pulando CV.")
  registrar_evento_log(
    etapa = "03_projecao",
    nivel = "INFO",
    mensagem = "Cache valido reutilizado",
    detalhe = CACHE_MODELOS_PATH
  )
  selecao_cv <- readRDS(CACHE_MODELOS_PATH)
} else {
  message("Iniciando CV two-stage: ", length(ids), " séries × ",
          length(MODELOS), " modelos, horizontes = ",
          paste(HORIZONTES_CV, collapse = "+"), "...")
  registrar_evento_log(
    etapa = "03_projecao",
    nivel = "INFO",
    mensagem = "Cache invalido ou ausente — iniciando CV two-stage",
    detalhe = CACHE_MODELOS_PATH
  )

  # --------------------------------------------------------------------------
  # Stage 1 — triagem rápida (approx=TRUE) para todos os modelos
  # --------------------------------------------------------------------------
  message("  Stage 1: triagem rapida (", length(MODELOS), " modelos × approx=TRUE)...")

  metricas_s1 <- map_dfr(seq_along(ids), function(i) {
    sid     <- ids[i]
    dados_s <- todas_series |> filter(serie_id == sid) |> arrange(ano)
    ts_obj  <- ts(dados_s$valor, start = min(dados_s$ano), frequency = 1)

    if (i %% 100 == 0 || i == 1)
      message("    [", i, "/", length(ids), "] ", sid)

    map_dfr(names(MODELOS), function(nm) {
      erros_mat <- cv_erros_multi(ts_obj, MODELOS[[nm]],
                                  serie_id = sid, modelo = nm,
                                  horizontes = HORIZONTES_CV)
      if (nrow(erros_mat) == 0L)
        return(tibble(serie_id = sid, modelo = nm, horizonte = HORIZONTES_CV,
                      n_ok = 0L, rmse = NA_real_, mae = NA_real_,
                      mase = NA_real_, mase_ponderado = NA_real_))
      metricas_multi(erros_mat, ts_obj, HORIZONTES_CV, PESOS_CV) |>
        mutate(serie_id = sid, modelo = nm)
    })
  })

  # Ponderado do stage 1 (uma linha por série × modelo)
  resumo_s1 <- metricas_s1 |>
    group_by(serie_id, modelo) |>
    slice(1) |>           # mase_ponderado é igual em todas as linhas do grupo
    ungroup() |>
    select(serie_id, modelo, mase_ponderado_s1 = mase_ponderado)

  # Top N_FINALISTAS finalistas por série (menor mase_ponderado no stage 1)
  finalistas <- resumo_s1 |>
    filter(!is.na(mase_ponderado_s1)) |>
    group_by(serie_id) |>
    slice_min(mase_ponderado_s1, n = N_FINALISTAS, with_ties = FALSE) |>
    ungroup()

  message("  Stage 1 concluido. Top ", N_FINALISTAS, " finalistas por serie.")

  # --------------------------------------------------------------------------
  # Stage 2 — avaliação precisa (approx=FALSE) apenas para finalistas
  # Modelos não-ARIMA têm especificação idêntica → reutiliza resultado s1.
  # ARIMA e ARMA recalculados com approx=FALSE.
  # --------------------------------------------------------------------------
  message("  Stage 2: avaliacao precisa (finalistas × approx=FALSE para ARIMA/ARMA)...")

  # Para séries anuais de ~22 obs, ordens acima de p/q=3 não têm suporte
  # estatístico — limitar o grid reduz drasticamente o tempo sem perda real.
  MODELOS_PRECISO <- MODELOS
  MODELOS_PRECISO$arima <- function(x, h) forecast(auto.arima(x,
                              stepwise = FALSE, approximation = FALSE,
                              max.p = 3, max.q = 3, max.d = 2,
                              max.P = 0, max.Q = 0, max.D = 0), h = h)
  MODELOS_PRECISO$arma  <- function(x, h) forecast(auto.arima(x, d = 0,
                              stepwise = FALSE, approximation = FALSE,
                              max.p = 3, max.q = 3,
                              max.P = 0, max.Q = 0, max.D = 0), h = h)
  MODELOS_ARIMA_EXACTOS <- c("arima", "arma")

  metricas_s2 <- map_dfr(seq_along(ids), function(i) {
    sid         <- ids[i]
    fins_sid    <- finalistas |> filter(serie_id == sid) |> pull(modelo)
    dados_s     <- todas_series |> filter(serie_id == sid) |> arrange(ano)
    ts_obj      <- ts(dados_s$valor, start = min(dados_s$ano), frequency = 1)

    map_dfr(fins_sid, function(nm) {
      # Reutiliza stage 1 para modelos sem diferença de especificação
      if (!nm %in% MODELOS_ARIMA_EXACTOS) {
        metricas_s1 |>
          filter(serie_id == sid, modelo == nm) |>
          mutate(stage = "s1_reused")
      } else {
        erros_mat <- cv_erros_multi(ts_obj, MODELOS_PRECISO[[nm]],
                                    serie_id = sid, modelo = nm,
                                    horizontes = HORIZONTES_CV)
        if (nrow(erros_mat) == 0L)
          return(tibble(serie_id = sid, modelo = nm, horizonte = HORIZONTES_CV,
                        n_ok = 0L, rmse = NA_real_, mae = NA_real_,
                        mase = NA_real_, mase_ponderado = NA_real_, stage = "s2"))
        metricas_multi(erros_mat, ts_obj, HORIZONTES_CV, PESOS_CV) |>
          mutate(serie_id = sid, modelo = nm, stage = "s2")
      }
    })
  })

  message("  Stage 2 concluido.")

  # --------------------------------------------------------------------------
  # Seleção final — vencedor por menor mase_ponderado do stage 2
  # --------------------------------------------------------------------------
  resumo_s2 <- metricas_s2 |>
    group_by(serie_id, modelo) |>
    slice(1) |>
    ungroup() |>
    select(serie_id, modelo, mase_ponderado = mase_ponderado)

  melhor <- resumo_s2 |>
    filter(!is.na(mase_ponderado)) |>
    group_by(serie_id) |>
    slice_min(mase_ponderado, n = 1, with_ties = FALSE) |>
    ungroup() |>
    select(serie_id, melhor_modelo = modelo, mase_ponderado)

  # Métricas por horizonte do vencedor (para diagnóstico)
  metricas_vencedor_h <- melhor |>
    left_join(metricas_s2 |> select(serie_id, modelo, horizonte, mase),
              by = c("serie_id", "melhor_modelo" = "modelo")) |>
    pivot_wider(names_from = horizonte, values_from = mase,
                names_prefix = "mase_venc_h") |>
    select(serie_id, starts_with("mase_venc_h"))

  # Tabela wide com mase_ponderado de todos os modelos (stage 1) para referência
  todas_metricas_wide <- resumo_s1 |>
    pivot_wider(names_from = modelo, values_from = mase_ponderado_s1,
                names_prefix = "mase_pond_")

  selecao_cv <- melhor |>
    left_join(metricas_vencedor_h, by = "serie_id") |>
    left_join(todas_metricas_wide,  by = "serie_id")

  # Salvar detalhamento completo por série × modelo × horizonte
  saveRDS(metricas_s1, "dados/metricas_cv_detalhadas.rds")
  message("Métricas CV detalhadas: ", nrow(metricas_s1), " linhas salvas.")

  salvar_cache_com_metadata(
    obj = selecao_cv,
    cache_path = CACHE_MODELOS_PATH,
    meta_path = CACHE_MODELOS_META_PATH,
    metadata_atual = metadata_cache_cv
  )
  message("CV two-stage concluído.")
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
                                  stepwise = FALSE, approximation = FALSE,
                                  max.p = 3, max.q = 3, max.d = 2,
                                  max.P = 0, max.Q = 0, max.D = 0), h = h)
MODELOS_FINAL$arma  <- function(x, h) forecast(auto.arima(x, d = 0,
                                  stepwise = FALSE, approximation = FALSE,
                                  max.p = 3, max.q = 3,
                                  max.P = 0, max.Q = 0, max.D = 0), h = h)

message("\nGerando projeções finais...")

projecoes_brutas <- map_dfr(ids, function(sid) {
  dados_s   <- todas_series |> filter(serie_id == sid) |> arrange(ano)
  ts_obj    <- ts(dados_s$valor, start = min(dados_s$ano), frequency = 1)
  modelo_nm <- selecao_cv |> filter(serie_id == sid) |> pull(melhor_modelo)

  if (length(modelo_nm) == 0 || is.na(modelo_nm)) modelo_nm <- "arima"

  fc <- executar_modelo_com_log(
    MODELOS_FINAL[[modelo_nm]](ts_obj, H),
    etapa = "projecao_final",
    serie_id = sid,
    modelo = modelo_nm
  )

  if (inherits(fc, "erro_modelo")) {
    motivo_fb <- fc$mensagem
    message("  Fallback ARIMA para: ", sid)
    fallback_log <<- bind_rows(fallback_log, tibble(
      serie_id        = sid,
      modelo_original = modelo_nm,
      modelo_fallback = "arima",
      etapa           = "projecao_final",
      motivo          = if (!is.null(motivo_fb)) motivo_fb else "erro_desconhecido"
    ))
    registrar_evento_log(
      etapa = "03_projecao",
      nivel = "WARNING",
      mensagem = "Fallback para ARIMA",
      detalhe = paste("serie_id =", sid, "| modelo_original =", modelo_nm)
    )
    modelo_nm <- "arima"
    fc <- executar_modelo_com_log(
      MODELOS_FINAL$arima(ts_obj, H),
      etapa = "fallback_arima",
      serie_id = sid,
      modelo = modelo_nm
    )
  }

  if (inherits(fc, "erro_modelo")) {
    stop("Falha definitiva na projeção final da série: ", sid)
  }

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

# Salvar log de fallbacks e verificar limiar de degradação
saveRDS(fallback_log, "dados/fallback_log.rds")
if (nrow(fallback_log) > 0L)
  message("Fallbacks registrados: ", nrow(fallback_log), " séries")

pct_fallback <- nrow(fallback_log) / length(ids)
if (pct_fallback > MAX_FALLBACK_PCT) {
  stop(sprintf(
    "Degradacao excessiva: %.1f%% de fallbacks (limite = %.0f%%)",
    pct_fallback * 100, MAX_FALLBACK_PCT * 100
  ))
}

# Tabela de parâmetros: uma linha por série com modelo selecionado e parâmetros
params_modelos <- projecoes_brutas |>
  distinct(serie_id, geo, geo_tipo, regiao, macrossetor, atividade, variavel,
           modelo, parametros) |>
  left_join(
    selecao_cv |> select(serie_id, mase_ponderado,
                         starts_with("mase_venc_h")),
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

registrar_evento_log(
  etapa = "03_projecao",
  nivel = "INFO",
  mensagem = "Resumo da modelagem",
  detalhe = paste(
    "series =", length(ids),
    "| cache =", if (cache_reutilizado) "reutilizado" else "recalculado",
    "| fallbacks =", nrow(fallback_log),
    "| pct_fallback =", round(nrow(fallback_log) / length(ids) * 100, 1), "%"
  )
)

message("\n03_projecao.R concluído.")
