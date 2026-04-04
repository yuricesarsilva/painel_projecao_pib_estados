args <- commandArgs(trailingOnly = TRUE)

projeto <- normalizePath(".", winslash = "/", mustWork = TRUE)
painel_dir <- file.path(projeto, "painel")
qmd <- file.path(painel_dir, "painel.qmd")

if (!file.exists(qmd)) {
  stop("Arquivo do painel nao encontrado em '", qmd, "'.", call. = FALSE)
}

linhas <- readLines(qmd, warn = FALSE, encoding = "UTF-8")
ini <- grep("^```\\{shinylive-r\\}", linhas)

if (length(ini) != 1L) {
  stop("Nao foi possivel localizar o bloco shinylive-r em painel/painel.qmd.", call. = FALSE)
}

fim_rel <- grep("^```\\s*$", linhas[(ini + 1L):length(linhas)])

if (length(fim_rel) < 1L) {
  stop("Nao foi possivel localizar o fim do bloco shinylive-r.", call. = FALSE)
}

fim <- ini + fim_rel[1L]
codigo <- linhas[(ini + 1L):(fim - 1L)]

codigo <- sub('BASE_URL <- "\\.\\./data"', 'BASE_URL <- "data"', codigo)
codigo <- sub('href = "\\.\\./metodologia\\.html"', 'href = "metodologia.html"', codigo)
codigo <- sub('shinyApp\\(ui, server\\)\\s*$', 'app <- shinyApp(ui, server)', codigo)

app_file <- tempfile("painel_local_", fileext = ".R")
writeLines(codigo, app_file, useBytes = TRUE)

dir_antigo <- getwd()
on.exit(setwd(dir_antigo), add = TRUE)
setwd(painel_dir)

source(app_file, local = TRUE, encoding = "UTF-8")

if (!exists("app", inherits = FALSE)) {
  stop("Falha ao montar o app local do painel.", call. = FALSE)
}

port <- if (length(args) >= 1L) as.integer(args[[1L]]) else NULL

shiny::runApp(
  app,
  launch.browser = TRUE,
  port = port
)
