PROJETO_CONFIG <- list(
  ANO_HIST_INI = 2002L,
  ANO_BASE = 2002L,
  ANO_HIST_FIM = 2023L,
  ANO_FIM = 2023L,
  H = 8L,
  ANO_PROJ_FIM = 2031L,
  MIN_TRAIN = 15L,
  HORIZONTES_CV = 1L,
  PESOS_CV = 1,
  SEED_GLOBAL = 12345L,
  R_VERSAO_PROJETO = "4.4.0",
  TOL_IDENTIDADE_PIB = 1e-06,
  TOL_RECONCILIACAO = 1e-06,
  LOG_DIR = "output/logs",
  CACHE_DIR = "dados",
  CACHE_SCHEMA_VERSION = "bloco2_v1",
  CACHE_MODELOS_PATH = "dados/selecao_modelos.rds",
  CACHE_MODELOS_META_PATH = "dados/selecao_modelos_meta.rds"
)

list2env(PROJETO_CONFIG, envir = .GlobalEnv)
