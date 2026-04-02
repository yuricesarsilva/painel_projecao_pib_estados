library(tidyverse)

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
# Cache do CV (03_projecao.R):
#   Se dados/selecao_modelos.rds existir, o CV é pulado e os modelos
#   salvos são reutilizados. IMPORTANTE: deletar o arquivo ao adicionar
#   novas séries (ex.: novas atividades) para forçar reprocessamento.
# ==============================================================================

scripts <- c(
  "R/01_leitura_dados.R",
  "R/02_consistencia.R",
  "R/03_projecao.R",
  "R/04_reconciliacao.R",
  "R/05_output.R"
)

t_total <- proc.time()

for (script in scripts) {
  cat("\n", strrep("=", 70), "\n", sep = "")
  cat("Executando:", script, "\n")
  cat(strrep("=", 70), "\n\n", sep = "")

  t0 <- proc.time()

  tryCatch(
    source(script, echo = FALSE, local = FALSE),
    error = function(e) {
      cat("\n*** ERRO em", script, "***\n")
      cat(conditionMessage(e), "\n")
      cat("Pipeline interrompido.\n")
      stop(e)
    }
  )

  elapsed <- round((proc.time() - t0)[["elapsed"]])
  cat("\n[OK]", script, "—", elapsed, "s\n")
}

cat("\n", strrep("=", 70), "\n", sep = "")
cat("Pipeline concluído em",
    round((proc.time() - t_total)[["elapsed"]]), "s\n")
cat(strrep("=", 70), "\n", sep = "")
