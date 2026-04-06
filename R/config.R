PROJETO_CONFIG <- list(
  ANO_HIST_INI = 2002L,
  ANO_BASE = 2002L,
  ANO_HIST_FIM = 2023L,
  ANO_FIM = 2023L,
  H = 8L,
  ANO_PROJ_FIM = 2031L,
  H_PAINEL = 3L,
  ANO_PAINEL_PROJ_FIM = 2026L,
  ANO_OPERACIONAL_FIM = 2026L,
  ANO_EXPLORATORIO_INI = 2027L,
  MIN_TRAIN = 15L,
  HORIZONTES_CV = c(1L, 2L, 3L),
  PESOS_CV = c(0.5, 0.3, 0.2),
  N_FINALISTAS = 3L,
  MAX_FALLBACK_PCT = 0.10,
  SEED_GLOBAL = 12345L,
  R_VERSAO_PROJETO = "4.4.0",
  TOL_IDENTIDADE_PIB = 1e-04,
  TOL_RECONCILIACAO = 1e-04,
  TOL_IMPOSTOS_SIDRA = 1,
  TOL_VAB_ATIVIDADES = 1,
  LOG_DIR = "output/logs",
  CACHE_DIR = "dados",
  CACHE_SCHEMA_VERSION = "bloco4_v1",
  CACHE_MODELOS_PATH = "dados/selecao_modelos.rds",
  CACHE_MODELOS_META_PATH = "dados/selecao_modelos_meta.rds",

  # Download IBGE
  IBGE_FTP_BASE          = "https://ftp.ibge.gov.br/Contas_Regionais",
  SIDRA_TABELA_ID        = 5938L,
  DOWNLOAD_DIR           = "base_bruta",
  STATUS_JSON_PATH       = "painel/data/status_dados.json",
  TOL_VALIDACAO_DOWNLOAD = 0.001   # desvio máximo aceitável na validação (0,1%)
)

list2env(PROJETO_CONFIG, envir = .GlobalEnv)
