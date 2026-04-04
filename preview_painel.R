args <- commandArgs(trailingOnly = TRUE)

projeto <- normalizePath(".", winslash = "/", mustWork = TRUE)
quarto <- "C:/Program Files/RStudio/resources/app/bin/quarto/bin/quarto.exe"
rprofile <- file.path(projeto, ".Rprofile")

if (!file.exists(quarto)) {
  stop("Quarto nao encontrado em '", quarto, "'.", call. = FALSE)
}

if (!file.exists(rprofile)) {
  stop(".Rprofile nao encontrado em '", rprofile, "'.", call. = FALSE)
}

Sys.setenv(R_PROFILE_USER = rprofile)

status <- system2(
  command = quarto,
  args = c("preview", "painel/painel.qmd", args),
  stdout = "",
  stderr = ""
)

if (!identical(status, 0L)) {
  stop("Falha ao abrir o preview do painel via Quarto.", call. = FALSE)
}
