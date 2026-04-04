args <- commandArgs(trailingOnly = TRUE)

projeto <- normalizePath(".", winslash = "/", mustWork = TRUE)
quarto <- "C:/Program Files/RStudio/resources/app/bin/quarto/bin/quarto.exe"
rprofile <- file.path(projeto, ".Rprofile")
activate <- file.path(projeto, "renv/activate.R")

if (!file.exists(quarto)) {
  stop("Quarto nao encontrado em '", quarto, "'.", call. = FALSE)
}

if (!file.exists(rprofile)) {
  stop(".Rprofile nao encontrado em '", rprofile, "'.", call. = FALSE)
}

if (!file.exists(activate)) {
  stop("renv/activate.R nao encontrado em '", activate, "'.", call. = FALSE)
}

source(activate, local = FALSE)
renv_lib <- normalizePath(.libPaths()[1], winslash = "/", mustWork = TRUE)

status <- system2(
  command = quarto,
  args = c("preview", "painel/painel.qmd", args),
  env = c(
    paste0("R_PROFILE_USER=", rprofile),
    paste0("R_LIBS_USER=", renv_lib),
    paste0("RENV_PROJECT=", projeto)
  ),
  stdout = "",
  stderr = ""
)

if (!identical(status, 0L)) {
  stop("Falha ao abrir o preview do painel via Quarto.", call. = FALSE)
}
