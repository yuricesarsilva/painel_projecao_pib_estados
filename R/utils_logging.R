obter_git_saida <- function(args) {
  tryCatch(
    system2("git", args, stdout = TRUE, stderr = FALSE),
    error = function(e) character()
  )
}

obter_git_commit <- function() {
  saida <- obter_git_saida(c("rev-parse", "HEAD"))
  if (length(saida) == 0) NA_character_ else saida[[1]]
}

obter_git_branch <- function() {
  saida <- obter_git_saida(c("branch", "--show-current"))
  if (length(saida) == 0) NA_character_ else saida[[1]]
}

inicializar_log_execucao <- function(prefixo = "pipeline", contexto = list()) {
  dir.create(LOG_DIR, recursive = TRUE, showWarnings = FALSE)

  log_id <- paste0(prefixo, "_", format(Sys.time(), "%Y%m%d_%H%M%S"))

  assign("LOG_EXECUCAO_ID", log_id, envir = .GlobalEnv)
  assign(
    "LOG_EVENTOS",
    data.frame(
      timestamp = character(),
      etapa = character(),
      nivel = character(),
      mensagem = character(),
      detalhe = character(),
      contexto = character(),
      stringsAsFactors = FALSE
    ),
    envir = .GlobalEnv
  )

  registrar_evento_log(
    etapa = prefixo,
    nivel = "INFO",
    mensagem = "Inicio da execucao",
    detalhe = NA_character_,
    contexto = contexto
  )

  invisible(log_id)
}

registrar_evento_log <- function(etapa,
                                 nivel = "INFO",
                                 mensagem,
                                 detalhe = NA_character_,
                                 contexto = list()) {
  if (!exists("LOG_EVENTOS", envir = .GlobalEnv, inherits = FALSE)) {
    return(invisible(NULL))
  }

  contexto_txt <- if (length(contexto) == 0) {
    NA_character_
  } else {
    paste(
      paste(names(contexto), unlist(contexto), sep = "="),
      collapse = "; "
    )
  }

  linha <- data.frame(
    timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    etapa = etapa,
    nivel = nivel,
    mensagem = mensagem,
    detalhe = detalhe,
    contexto = contexto_txt,
    stringsAsFactors = FALSE
  )

  log_eventos <- get("LOG_EVENTOS", envir = .GlobalEnv, inherits = FALSE)
  assign("LOG_EVENTOS", rbind(log_eventos, linha), envir = .GlobalEnv)

  invisible(NULL)
}

salvar_log_execucao <- function(status = "concluido") {
  if (!exists("LOG_EVENTOS", envir = .GlobalEnv, inherits = FALSE) ||
      !exists("LOG_EXECUCAO_ID", envir = .GlobalEnv, inherits = FALSE)) {
    return(invisible(NULL))
  }

  registrar_evento_log(
    etapa = "pipeline",
    nivel = "INFO",
    mensagem = "Fim da execucao",
    detalhe = status
  )

  log_id <- get("LOG_EXECUCAO_ID", envir = .GlobalEnv, inherits = FALSE)
  log_eventos <- get("LOG_EVENTOS", envir = .GlobalEnv, inherits = FALSE)

  write.csv(
    log_eventos,
    file.path(LOG_DIR, paste0(log_id, ".csv")),
    row.names = FALSE,
    na = ""
  )

  saveRDS(
    log_eventos,
    file.path(LOG_DIR, paste0(log_id, ".rds"))
  )

  invisible(log_id)
}
