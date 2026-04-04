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
#     → dados/selecao_modelos.rds    (cache CV — melhor modelo por série)
#     → dados/projecoes_brutas.rds   (proj + IC 95% por série × ano)
#     → dados/params_modelos.rds     (modelo, parâmetros, MASE, RMSE)
#     → dados/vab_macro_hist.rds     (histórico VAB macro para gráficos)
#     → dados/vab_atividade_hist.rds (histórico VAB atividade para gráficos)
#     → dados/vab_macrossetor_proj.rds
#     → dados/vab_atividade_proj.rds (proj + IC por atividade × geo × ano)
#     → dados/projecoes_derivadas.rds (PIB, VAB, impostos, deflator, cresc.)
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
#   A seleção de modelos usa metadata com hashes dos insumos, parâmetros e do
#   script. O cache é reutilizado apenas quando a assinatura continua válida.
# ==============================================================================

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
