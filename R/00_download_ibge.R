source("R/config.R", local = FALSE)

# Pacotes necessários (instalar antes da primeira execução, se ausentes):
#   renv::install(c("httr2", "sidrar", "jsonlite", "openxlsx"))
#   renv::snapshot()
library(httr2)
library(sidrar)
library(jsonlite)
library(openxlsx)
library(tidyverse)

# ==============================================================================
# 00_download_ibge.R
#
# Baixa automaticamente os dados brutos das Contas Regionais do IBGE e salva
# em base_bruta/, pronto para ser lido por R/01_leitura_dados.R.
#
# Fontes:
#   FTP IBGE — Conta da Produção e Especiais (ZIPs com XLS)
#     URL padrão: IBGE_FTP_BASE/{ANO_HIST_FIM}/xls/
#   SIDRA — tabela 5938 (PIB + impostos líquidos + VAB por UF)
#
# Comportamento:
#   - Download e extração em pasta temporária base_bruta/_novo/
#   - Validação cruzada com dados/especiais.rds (se existir)
#   - Somente após validação bem-sucedida as pastas são promovidas
#   - Status gravado em STATUS_JSON_PATH (painel/data/status_dados.json)
#   - Em caso de erro, status com código é gravado antes de interromper
#
# Códigos de erro:
#   E01 — URL 404: IBGE mudou o caminho do FTP
#   E02 — Timeout ou falha de rede
#   E03 — Validação falhou: valores divergem além de TOL_VALIDACAO_DOWNLOAD
#   E04 — ZIP corrompido ou falha na extração
#   E05 — SIDRA indisponível ou parâmetros inválidos
#
# Para acionar a partir do pipeline:
#   DOWNLOAD_ANTES_DE_RODAR <- TRUE
#   source("R/run_all.R")
#
# Para acionar isoladamente:
#   source("R/00_download_ibge.R")
# ==============================================================================

# ==============================================================================
# Funções auxiliares
# ==============================================================================

gravar_status <- function(status, ano_ini, ano_fim,
                          codigo_erro = NULL, mensagem_erro = NULL) {
  dir.create(dirname(STATUS_JSON_PATH), showWarnings = FALSE, recursive = TRUE)
  obj <- list(
    status        = status,
    ano_ini       = ano_ini,
    ano_fim       = ano_fim,
    data_download = format(Sys.time(), "%Y-%m-%d %H:%M"),
    codigo_erro   = if (is.null(codigo_erro)) NA_character_ else codigo_erro,
    mensagem_erro = if (is.null(mensagem_erro)) NA_character_ else mensagem_erro
  )
  write_json(obj, STATUS_JSON_PATH, auto_unbox = TRUE, null = "null")
}

parar_com_codigo <- function(codigo, detalhe = "") {
  desc <- switch(codigo,
    E01 = "URL nao encontrada (404) — IBGE pode ter mudado o caminho do FTP",
    E02 = "Timeout ou falha de rede",
    E03 = "Validacao falhou — valores divergem dos dados atuais alem da tolerancia",
    E04 = "ZIP corrompido ou falha na extracao",
    E05 = "SIDRA indisponivel ou parametros invalidos",
    paste("Erro desconhecido:", codigo)
  )
  mensagem <- if (nchar(detalhe) > 0) paste0(desc, " | ", detalhe) else desc
  gravar_status("erro", ANO_HIST_INI, ANO_HIST_FIM,
                codigo_erro = codigo, mensagem_erro = mensagem)
  stop(paste0("[", codigo, "] ", mensagem), call. = FALSE)
}

baixar_zip <- function(url, destino) {
  message("Baixando: ", url)
  resp <- tryCatch(
    request(url) |>
      req_timeout(300) |>
      req_retry(max_tries = 2, backoff = ~ 10) |>
      req_perform(),
    error = function(e) {
      msg <- conditionMessage(e)
      if (grepl("timeout|timed out|Timeout", msg, ignore.case = TRUE))
        parar_com_codigo("E02", msg)
      parar_com_codigo("E02", msg)
    }
  )
  if (resp_status(resp) == 404L)
    parar_com_codigo("E01", url)
  if (resp_status(resp) >= 400L)
    parar_com_codigo("E02", paste("HTTP", resp_status(resp), url))
  writeBin(resp_body_raw(resp), destino)
  message("Salvo: ", destino)
}

extrair_zip <- function(zip_path, destino_dir) {
  result <- tryCatch(
    unzip(zip_path, exdir = destino_dir),
    error = function(e) parar_com_codigo("E04", conditionMessage(e))
  )
  if (length(result) == 0)
    parar_com_codigo("E04", paste("Nenhum arquivo extraido de:", zip_path))
  message("Extraido: ", length(result), " arquivos em ", destino_dir)
  invisible(result)
}

# ==============================================================================
# Passo 1 — Montar URLs
# ==============================================================================

message("\n=== 00_download_ibge.R ===")
message("Periodo alvo: ", ANO_HIST_INI, "-", ANO_HIST_FIM)

url_base  <- paste0(IBGE_FTP_BASE, "/", ANO_HIST_FIM, "/xls")
nome_esp  <- paste0("Especiais_",         ANO_HIST_INI, "_", ANO_HIST_FIM, "_xls")
nome_cp   <- paste0("Conta_da_Producao_", ANO_HIST_INI, "_", ANO_HIST_FIM, "_xls")

url_esp   <- paste0(url_base, "/", nome_esp, ".zip")
url_cp    <- paste0(url_base, "/", nome_cp,  ".zip")

message("URL Especiais:        ", url_esp)
message("URL Conta da Producao:", url_cp)

# ==============================================================================
# Passo 2 — Download para pasta temporária
# ==============================================================================

dir_novo <- file.path(DOWNLOAD_DIR, "_novo")
dir.create(dir_novo, showWarnings = FALSE, recursive = TRUE)

zip_esp <- file.path(dir_novo, paste0(nome_esp, ".zip"))
zip_cp  <- file.path(dir_novo, paste0(nome_cp,  ".zip"))

baixar_zip(url_esp, zip_esp)
baixar_zip(url_cp,  zip_cp)

# ==============================================================================
# Passo 3 — Extrair ZIPs
# ==============================================================================

message("Extraindo ZIPs...")
# Extrair cada ZIP para seu próprio subdiretório, reproduzindo a estrutura de base_bruta/
dir_esp_novo <- file.path(dir_novo, nome_esp)
dir_cp_novo  <- file.path(dir_novo, nome_cp)
dir.create(dir_esp_novo, showWarnings = FALSE)
dir.create(dir_cp_novo,  showWarnings = FALSE)
extrair_zip(zip_esp, dir_esp_novo)
extrair_zip(zip_cp,  dir_cp_novo)

# Remover ZIPs após extração
unlink(zip_esp)
unlink(zip_cp)

# ==============================================================================
# Passo 4 — Download SIDRA (tabela 5938)
# ==============================================================================

message("Baixando SIDRA tabela ", SIDRA_TABELA_ID, " (impostos por UF)...")

# Variáveis da tabela 5938:
#   37  — PIB a preços correntes (R$ milhares)
#   513 — Impostos, líquidos de subsídios (R$ milhares)
#   6293— VAB a preços correntes (R$ milhares)
# Nível geográfico: Estados (N3) + Regiões (N2) + Brasil (N1)
periodos <- as.character(ANO_HIST_INI:ANO_HIST_FIM)

# Variáveis da tabela 5938 (códigos SIDRA):
#   37  — PIB a preços correntes
#   543 — Impostos líquidos de subsídios sobre produtos
#   498 — VAB a preços correntes total
# Nota: cada nível geográfico retorna coluna de nome diferente
# ("Brasil", "Grande Região", "Unidade da Federação") — normalizar antes do bind_rows

colunas_padrao_sidra <- c(
  "Nível Territorial (Código)", "Nível Territorial",
  "Unidade de Medida (Código)", "Unidade de Medida",
  "Ano (Código)", "Ano", "Variável (Código)", "Variável", "Valor"
)

normalizar_sidra <- function(df) {
  # Identifica a coluna de geo: a única que não é padrão e não termina em " (Código)"
  cols_codigo <- grep("\\(Código\\)$", names(df), value = TRUE)
  col_geo <- setdiff(names(df), c(colunas_padrao_sidra, cols_codigo))
  col_geo <- col_geo[1]
  df |>
    select(geo = all_of(col_geo), ano = Ano, var = `Variável`, valor = Valor) |>
    mutate(ano = as.integer(ano), valor = as.numeric(valor))
}

sidra_wide <- tryCatch({
  br   <- normalizar_sidra(get_sidra(5938L, variable = c(37L, 543L, 498L),
                                     period = periodos, geo = "Brazil"))
  regs <- normalizar_sidra(get_sidra(5938L, variable = c(37L, 543L, 498L),
                                     period = periodos, geo = "Region"))
  ufs  <- normalizar_sidra(get_sidra(5938L, variable = c(37L, 543L, 498L),
                                     period = periodos, geo = "State"))
  bind_rows(br, regs, ufs) |>
    pivot_wider(names_from = var, values_from = valor)
}, error = function(e) parar_com_codigo("E05", conditionMessage(e)))

# Salvar como XLSX (reproduzindo a estrutura esperada por 01_leitura_dados.R)
# Aba 1 = PIB, Aba 2 = Impostos  (convenção do arquivo SIDRA original)
sidra_path_novo <- file.path(dir_novo, "PIB e Impostos (SIDRA).xlsx")

# Identificar colunas de PIB e impostos pelo padrão do nome
col_pib <- grep("(?i)produto interno bruto a pre", names(sidra_wide), value = TRUE, perl = TRUE)[1]
col_imp <- grep("(?i)impostos.*l.quidos",          names(sidra_wide), value = TRUE, perl = TRUE)[1]
message("Coluna PIB: ", col_pib)
message("Coluna Impostos: ", col_imp)

# O reader (ler_especial_simples) lê com col_names=FALSE e espera:
#   Linha 4: células 2..(N_ANOS+1) = anos (2002..ANO_HIST_FIM)
#   Linhas 5..37: célula 1 = geo, células 2..(N_ANOS+1) = valores
# Usa startRow para escrever na linha exata — linhas 1-3 ficam vazias.
anos_vec <- sort(unique(sidra_wide$ano))

escrever_aba_sidra <- function(wb, sheet_name, col_valor) {
  vals_wide <- sidra_wide |>
    select(geo, ano, valor = all_of(col_valor)) |>
    pivot_wider(names_from = ano, values_from = valor)

  # Linhas 1-3: preenchimento para que read_xls não as salte (readxl ignora
  # linhas inicialmente vazias e desloca a numeração)
  n_cols <- length(anos_vec) + 1L
  filler <- as.data.frame(matrix(".", nrow = 3L, ncol = n_cols))
  writeData(wb, sheet_name, filler, startRow = 1L, colNames = FALSE)

  # Linha 4: NA na col 1, depois os anos
  header_df <- as.data.frame(matrix(c(NA_real_, anos_vec), nrow = 1L))
  writeData(wb, sheet_name, header_df, startRow = 4L, colNames = FALSE)

  # Linhas 5+: dados (geo + valores)
  writeData(wb, sheet_name, vals_wide, startRow = 5L, colNames = FALSE)
}

wb <- createWorkbook()
addWorksheet(wb, "PIB")
addWorksheet(wb, "Impostos")
escrever_aba_sidra(wb, "PIB",      col_pib)
escrever_aba_sidra(wb, "Impostos", col_imp)
saveWorkbook(wb, sidra_path_novo, overwrite = TRUE)
message("SIDRA salvo: ", sidra_path_novo)

# ==============================================================================
# Passo 5 — Validação cruzada
# ==============================================================================

if (file.exists("dados/especiais.rds")) {
  message("Validando dados baixados contra dados/especiais.rds atual...")

  # Executar leitura temporária apontando para _novo/
  env_temp <- new.env(parent = .GlobalEnv)
  env_temp$ANO_HIST_INI <- ANO_HIST_INI
  env_temp$ANO_HIST_FIM <- ANO_HIST_FIM

  # Override dos caminhos para apontar ao diretório temporário
  env_temp$BASE_OVERRIDE <- dir_novo

  # Leitura simplificada para validação: apenas tab01 (PIB nominal)
  esp_novo_pib <- tryCatch({
    library(readxl)
    arq_tab01 <- file.path(dir_novo, nome_esp, "tab01.xls")
    n_anos <- ANO_HIST_FIM - ANO_HIST_INI + 1L
    df <- read_xls(arq_tab01, sheet = 1, col_names = FALSE, .name_repair = "minimal")
    anos <- as.numeric(df[4, 2:(n_anos + 1L)])
    df[5:37, 1:(n_anos + 1L)] |>
      set_names(c("geo", paste0("Y", anos))) |>
      mutate(across(everything(), as.character)) |>
      filter(!is.na(geo), !stringr::str_starts(geo, "Fonte")) |>
      pivot_longer(-geo, names_to = "ano", names_prefix = "Y", values_to = "valor") |>
      mutate(ano = as.integer(ano), valor = as.numeric(valor))
  }, error = function(e) parar_com_codigo("E04", conditionMessage(e)))

  esp_atual <- readRDS("dados/especiais.rds")
  pib_atual <- esp_atual |>
    filter(variavel == "pib_nominal", geo == "Brasil") |>
    select(ano, valor_atual = valor)

  pib_novo <- esp_novo_pib |>
    filter(geo == "Brasil") |>
    select(ano, valor_novo = valor)

  # Comparar anos comuns excluindo o mais recente (pode ter revisão)
  anos_comparar <- intersect(pib_atual$ano, pib_novo$ano)
  anos_comparar <- anos_comparar[anos_comparar < max(anos_comparar)]

  if (length(anos_comparar) > 0) {
    comp <- pib_atual |>
      filter(ano %in% anos_comparar) |>
      left_join(pib_novo |> filter(ano %in% anos_comparar), by = "ano") |>
      mutate(desvio = abs(valor_novo - valor_atual) / abs(valor_atual))

    desvio_max <- max(comp$desvio, na.rm = TRUE)
    message("Desvio máximo PIB Brasil (anos ", min(anos_comparar), "-",
            max(anos_comparar), "): ", round(desvio_max * 100, 4), "%")

    if (desvio_max > TOL_VALIDACAO_DOWNLOAD) {
      parar_com_codigo("E03",
        paste0("Desvio máximo = ", round(desvio_max * 100, 4),
               "% (limite = ", TOL_VALIDACAO_DOWNLOAD * 100, "%)",
               " — possível revisão metodológica do IBGE. Validar manualmente."))
    }
    message("Validação OK — dados consistentes com a base atual.")
  } else {
    message("Sem anos em comum para validação (novo período?). Pulando validação.")
  }
} else {
  message("dados/especiais.rds não encontrado — pulando validação cruzada.")
}

# ==============================================================================
# Passo 6 — Promover _novo/ → base_bruta/ e gravar status de sucesso
# ==============================================================================

message("Promovendo dados novos para base_bruta/...")

# Remover pastas antigas e mover as novas
dir_esp_antigo  <- file.path(DOWNLOAD_DIR, nome_esp)
dir_cp_antigo   <- file.path(DOWNLOAD_DIR, nome_cp)
dir_esp_novo    <- file.path(dir_novo, nome_esp)
dir_cp_novo     <- file.path(dir_novo, nome_cp)
sidra_antigo    <- file.path(DOWNLOAD_DIR, "PIB e Impostos (SIDRA).xlsx")

if (dir.exists(dir_esp_antigo))  unlink(dir_esp_antigo, recursive = TRUE)
if (dir.exists(dir_cp_antigo))   unlink(dir_cp_antigo,  recursive = TRUE)
if (file.exists(sidra_antigo))   unlink(sidra_antigo)

mover_item <- function(src, dst) {
  ok <- suppressWarnings(file.rename(src, dst))
  if (!isTRUE(ok)) {
    if (dir.exists(src)) {
      file.copy(src, dirname(dst), recursive = TRUE, overwrite = TRUE)
      unlink(src, recursive = TRUE)
    } else {
      file.copy(src, dst, overwrite = TRUE)
      unlink(src)
    }
  }
}

mover_item(dir_esp_novo,    dir_esp_antigo)
mover_item(dir_cp_novo,     dir_cp_antigo)
mover_item(sidra_path_novo, sidra_antigo)

# Limpar pasta temporária
unlink(dir_novo, recursive = TRUE)

gravar_status("ok", ANO_HIST_INI, ANO_HIST_FIM)

message("\nDownload concluido.")
message("  Especiais:         ", dir_esp_antigo)
message("  Conta da Producao: ", dir_cp_antigo)
message("  SIDRA:             ", sidra_antigo)
message("  Status:            ", STATUS_JSON_PATH)
