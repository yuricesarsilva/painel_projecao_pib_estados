source("R/config.R", local = FALSE)
source("R/utils_logging.R", local = FALSE)

# ==============================================================================
# run_all.R
#
# Executa o pipeline completo de projeções dos PIBs estaduais em sequência.
# Rode este script a partir da raiz do projeto (diretório com .Rproj).
#
# Ordem de execução e saídas principais:
#   01_leitura_dados.R
#     → dados/especiais.rds          (PIB, VAB, impostos, vol. encadeado)
#     → dados/conta_producao.rds     (VBP/CI/VAB por atividade × geo × ano)
#
#   02_consistencia.R
#     → dados/consistencia.rds       (resultados das 5 checagens contábeis)
#
#   03_projecao.R                    (~1.089 séries: macro + impostos + ativ.)
#     → dados/selecao_modelos.rds       (cache CV two-stage — melhor modelo por série)
#     → dados/selecao_modelos_meta.rds  (metadata de invalidação do cache)
#     → dados/metricas_cv_detalhadas.rds (métricas por série × modelo × horizonte)
#     → dados/projecoes_brutas.rds      (proj + IC 95% por série × ano)
#     → dados/params_modelos.rds        (modelo, parâmetros, mase_ponderado,
#                                         mase_venc_h1/h2/h3 por série)
#     → dados/fallback_log.rds          (log de fallbacks para ARIMA)
#     → dados/vab_macro_hist.rds        (histórico VAB macro para gráficos)
#     → dados/vab_atividade_hist.rds    (histórico VAB atividade para gráficos)
#     → dados/vab_macrossetor_proj.rds
#     → dados/vab_atividade_proj.rds    (proj + IC por atividade × geo × ano)
#     → dados/projecoes_derivadas.rds   (PIB, VAB, impostos, deflator, cresc.)
#
#   04_reconciliacao.R               (benchmarking top-down: BR → reg → UF)
#     → dados/projecoes_reconciliadas.rds
#     → dados/vab_macro_reconciliado.rds
#     → dados/vab_atividade_reconciliada.rds
#
#   05_output.R
#     → output/tabelas/projecoes_pib_estadual.xlsx  (9 abas)
#     → output/graficos/todas_geos/   (21 plots facetados)
#     → output/graficos/por_geo/      (33 plots por território)
#     → output/graficos/por_geo_atividade/  (33 stacked-area plots)
#     → output/graficos/series_brutas/      (9 plots séries brutas)
#     → output/graficos/              (5 plots de resumo)
#
#   06_exportar_painel.R
#     → painel/data/serie_principal.csv  (histórico+proj, 5 variáveis, IC 95%)
#     → painel/data/vab_macrossetor.csv  (histórico+proj por macrossetor, IC 95%)
#     → painel/data/vab_atividade.csv    (histórico+proj por atividade, IC 95%)
#     (CSVs versionados no git — usados pelo painel Quarto+shinylive no
#      GitHub Pages. Executar 06 após qualquer atualização do pipeline.)
#
# Cache do CV (03_projecao.R):
#   A seleção usa CV two-stage expanding-window (h=1/2/3, MASE ponderado).
#   A metadata inclui hashes dos insumos, parâmetros e do script — o cache
#   é reutilizado apenas quando a assinatura continua válida.
#   Schema: CACHE_SCHEMA_VERSION = "bloco4_v1" (R/config.R).
# ==============================================================================

# ==============================================================================
# Etapa 0 — Download IBGE (opcional)
#
# Por padrão desativado — útil quando a base já está atualizada localmente.
# Para ativar antes de rodar o pipeline:
#   DOWNLOAD_ANTES_DE_RODAR <- TRUE
#   source("R/run_all.R")
# ==============================================================================
if (!exists("DOWNLOAD_ANTES_DE_RODAR")) DOWNLOAD_ANTES_DE_RODAR <- FALSE

if (isTRUE(DOWNLOAD_ANTES_DE_RODAR)) {
  cat("\n", strrep("=", 70), "\n", sep = "")
  cat("Etapa 0: Download IBGE\n")
  cat(strrep("=", 70), "\n\n", sep = "")
  registrar_evento_log("run_all", "INFO", "Etapa 0: iniciando download IBGE")
  source("R/00_download_ibge.R", local = FALSE)
  registrar_evento_log("run_all", "INFO", "Etapa 0: download IBGE concluido")
}

scripts <- c(
  "R/01_leitura_dados.R",
  "R/02_consistencia.R",
  "R/03_projecao.R",
  "R/04_reconciliacao.R",
  "R/05_output.R",
  "R/06_exportar_painel.R"
)

t_total <- proc.time()
set.seed(SEED_GLOBAL)

inicializar_log_execucao(
  prefixo = "run_all",
  contexto = list(
    branch = obter_git_branch(),
    commit = obter_git_commit(),
    seed = SEED_GLOBAL,
    r_version = R.version.string
  )
)

registrar_evento_log(
  etapa = "run_all",
  nivel = "INFO",
  mensagem = "Pipeline iniciado",
  detalhe = paste(scripts, collapse = " | ")
)

for (script in scripts) {
  cat("\n", strrep("=", 70), "\n", sep = "")
  cat("Executando:", script, "\n")
  cat(strrep("=", 70), "\n\n", sep = "")

  t0 <- proc.time()
  registrar_evento_log("run_all", "INFO", "Inicio de script", script)

  tryCatch(
    source(script, echo = FALSE, local = FALSE),
    error = function(e) {
      registrar_evento_log(
        etapa = "run_all",
        nivel = "ERROR",
        mensagem = "Falha na execucao de script",
        detalhe = paste(script, "-", conditionMessage(e))
      )
      salvar_log_execucao(status = "erro")
      cat("\n*** ERRO em", script, "***\n")
      cat(conditionMessage(e), "\n")
      cat("Pipeline interrompido.\n")
      stop(e)
    }
  )

  if (identical(script, "R/02_consistencia.R") &&
      exists("qa_status", envir = .GlobalEnv, inherits = FALSE)) {
    qa_status_atual <- get("qa_status", envir = .GlobalEnv, inherits = FALSE)

    if (!isTRUE(qa_status_atual$ok)) {
      registrar_evento_log(
        etapa = "run_all",
        nivel = "ERROR",
        mensagem = "QA bloqueante interrompeu o pipeline",
        detalhe = paste(
          qa_status_atual$erros_fatais$check,
          collapse = ", "
        )
      )
      salvar_log_execucao(status = "erro_qa")
      stop("QA bloqueante falhou em R/02_consistencia.R. Pipeline interrompido.")
    }
  }

  elapsed <- round((proc.time() - t0)[["elapsed"]])
  registrar_evento_log(
    etapa = "run_all",
    nivel = "INFO",
    mensagem = "Fim de script",
    detalhe = paste(script, "-", elapsed, "s")
  )
  cat("\n[OK]", script, "—", elapsed, "s\n")
}

salvar_log_execucao(status = "sucesso")

cat("\n", strrep("=", 70), "\n", sep = "")
cat("Pipeline concluído em",
    round((proc.time() - t_total)[["elapsed"]]), "s\n")
cat(strrep("=", 70), "\n", sep = "")
