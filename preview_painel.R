args <- commandArgs(trailingOnly = TRUE)

projeto <- normalizePath(".", winslash = "/", mustWork = TRUE)
rprofile <- file.path(projeto, ".Rprofile")
renv_lib <- file.path(projeto, "renv", "library", "windows", "R-4.4", "x86_64-w64-mingw32")

find_quarto <- function() {
  candidates <- c(
    Sys.which("quarto"),
    "C:/Program Files/Quarto/bin/quarto.exe",
    "C:/Program Files/RStudio/resources/app/bin/quarto/bin/quarto.exe"
  )
  candidates <- unique(normalizePath(candidates[nzchar(candidates)], winslash = "/", mustWork = FALSE))
  match <- candidates[file.exists(candidates)][1]

  if (is.na(match)) {
    stop(
      "Quarto nao encontrado. Instale o Quarto CLI ou use uma instalacao do RStudio com Quarto embutido.",
      call. = FALSE
    )
  }

  match
}

find_rscript <- function() {
  command <- Sys.which("Rscript")
  if (nzchar(command)) {
    return(normalizePath(command, winslash = "/", mustWork = TRUE))
  }

  user_r <- file.path(Sys.getenv("LOCALAPPDATA"), "Programs", "R")
  candidates <- character()
  if (dir.exists(user_r)) {
    found <- list.files(
      user_r,
      pattern = "^Rscript\\.exe$",
      recursive = TRUE,
      full.names = TRUE,
      ignore.case = TRUE
    )
    candidates <- c(found, candidates)
  }

  candidates <- c(
    candidates,
    "C:/Program Files/R/R-4.4.0/bin/Rscript.exe",
    "C:/Program Files/R/R-4.4.0/bin/x64/Rscript.exe"
  )

  candidates <- unique(normalizePath(candidates, winslash = "/", mustWork = FALSE))
  match <- candidates[file.exists(candidates)][1]

  if (is.na(match)) {
    stop("Rscript nao encontrado. Instale o R 4.4.x ou adicione o Rscript ao PATH.", call. = FALSE)
  }

  match
}

quarto <- find_quarto()
rscript <- find_rscript()
r_bin <- dirname(rscript)
r_home <- dirname(r_bin)

if (!file.exists(quarto)) {
  stop("Quarto nao encontrado em '", quarto, "'.", call. = FALSE)
}

if (!dir.exists(r_bin)) {
  stop("Diretorio do R nao encontrado em '", r_bin, "'.", call. = FALSE)
}

if (!file.exists(rprofile)) {
  stop(".Rprofile nao encontrado em '", rprofile, "'.", call. = FALSE)
}

if (!dir.exists(renv_lib)) {
  stop("Biblioteca local do renv nao encontrada em '", renv_lib, "'.", call. = FALSE)
}

renv_lib <- normalizePath(renv_lib, winslash = "/", mustWork = TRUE)

env_antigo <- Sys.getenv(
  c("R_PROFILE_USER", "R_LIBS_USER", "RENV_PROJECT", "R_HOME", "PATH"),
  unset = NA
)
on.exit({
  if (is.na(env_antigo[["R_PROFILE_USER"]])) Sys.unsetenv("R_PROFILE_USER") else Sys.setenv(R_PROFILE_USER = env_antigo[["R_PROFILE_USER"]])
  if (is.na(env_antigo[["R_LIBS_USER"]])) Sys.unsetenv("R_LIBS_USER") else Sys.setenv(R_LIBS_USER = env_antigo[["R_LIBS_USER"]])
  if (is.na(env_antigo[["RENV_PROJECT"]])) Sys.unsetenv("RENV_PROJECT") else Sys.setenv(RENV_PROJECT = env_antigo[["RENV_PROJECT"]])
  if (is.na(env_antigo[["R_HOME"]])) Sys.unsetenv("R_HOME") else Sys.setenv(R_HOME = env_antigo[["R_HOME"]])
  if (is.na(env_antigo[["PATH"]])) Sys.unsetenv("PATH") else Sys.setenv(PATH = env_antigo[["PATH"]])
}, add = TRUE)

path_sep <- .Platform$path.sep
path_novo <- paste(c(normalizePath(r_bin, winslash = "/", mustWork = TRUE), env_antigo[["PATH"]]), collapse = path_sep)

Sys.setenv(
  R_PROFILE_USER = rprofile,
  R_LIBS_USER = renv_lib,
  RENV_PROJECT = projeto,
  R_HOME = normalizePath(r_home, winslash = "/", mustWork = TRUE),
  PATH = path_novo
)

status <- system2(
  command = quarto,
  args = c("preview", "painel/painel.qmd", args),
  stdout = "",
  stderr = ""
)

if (!identical(status, 0L)) {
  stop("Falha ao abrir o preview do painel via Quarto.", call. = FALSE)
}
