hash_arquivo <- function(path) {
  if (!file.exists(path)) {
    return(NA_character_)
  }

  unname(tools::md5sum(path))
}

hash_objeto <- function(x) {
  tmp <- tempfile(fileext = ".rds")
  on.exit(unlink(tmp), add = TRUE)
  saveRDS(x, tmp)
  hash_arquivo(tmp)
}

criar_metadata_cache <- function(nome,
                                 objetos = list(),
                                 arquivos = list(),
                                 parametros = list(),
                                 script_path = NULL) {
  hashes_objetos <- lapply(objetos, hash_objeto)
  hashes_arquivos <- lapply(arquivos, hash_arquivo)
  hash_script <- if (!is.null(script_path)) hash_arquivo(script_path) else NA_character_

  assinatura <- hash_objeto(list(
    nome = nome,
    objetos = hashes_objetos,
    arquivos = hashes_arquivos,
    parametros = parametros,
    script = hash_script
  ))

  list(
    nome = nome,
    timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    hashes_objetos = hashes_objetos,
    hashes_arquivos = hashes_arquivos,
    parametros = parametros,
    hash_script = hash_script,
    assinatura = assinatura
  )
}

cache_valido <- function(cache_path, meta_path, metadata_atual) {
  if (!file.exists(cache_path) || !file.exists(meta_path)) {
    return(FALSE)
  }

  metadata_salva <- readRDS(meta_path)
  identical(metadata_salva$assinatura, metadata_atual$assinatura)
}

salvar_cache_com_metadata <- function(obj, cache_path, meta_path, metadata_atual) {
  dir.create(dirname(cache_path), recursive = TRUE, showWarnings = FALSE)
  dir.create(dirname(meta_path), recursive = TRUE, showWarnings = FALSE)
  saveRDS(obj, cache_path)
  saveRDS(metadata_atual, meta_path)
}
