library(tidyverse)
library(readxl)

# ==============================================================================
# 01_leitura_dados.R
#
# Lê todas as fontes brutas de dados e salva dois arquivos .rds em dados/.
#
# Fontes em base_bruta/:
#   Especiais_2002_2023_xls/
#     tab01.xls — PIB nominal (27 UFs + 5 regiões + Brasil, 2002–2023)
#     tab03.xls — Série encadeada do volume do PIB (índice, base 2010=100)
#     tab04.xls — VAB nominal total
#     tab05.xls — Série encadeada do volume do VAB por atividade (13 abas)
#   Conta_da_Producao_2002_2023_xls/
#     Tabela1.xls a Tabela33.xls — VBP, CI e VAB por atividade:
#       val_ano_ant, idx_volume, val_preco_ant, idx_preco, val_corrente
#       (33 geos × 13 atividades × 3 blocos × 22 anos = 28.314 linhas)
#   PIB e Impostos (SIDRA).xlsx — impostos líquidos de subsídios nominais
#     (em R$ mil → convertido para R$ milhões na leitura)
#     Impostos faltantes (anos mais recentes sem cobertura SIDRA) são
#     imputados via identidade contábil: Impostos = PIB − VAB
#
# Notas:
#   - Unidade monetária uniforme: R$ milhões.
#   - Índices de volume e preço começam em 2003 (2002 só tem val_corrente).
#   - Acre possui NAs em val_corrente no ano 2002 para algumas atividades
#     (limitação do arquivo original do IBGE — não afeta anos projetados).
#   - Tabela19.xls (Sudeste) tem nomes de abas não padrão; corrigido pelo
#     uso de índice posicional de aba em vez de nome.
#
# Saídas:
#   dados/especiais.rds     — PIB, VAB, impostos, vol. encadeado (tidy)
#   dados/conta_producao.rds — VBP/CI/VAB por atividade × geo × ano (tidy)
# ==============================================================================

# ==============================================================================
# Caminhos
# ==============================================================================

BASE       <- "base_bruta"
ESPECIAIS  <- file.path(BASE, "Especiais_2002_2023_xls")
CONTA_PROD <- file.path(BASE, "Conta_da_Producao_2002_2023_xls")
SIDRA      <- file.path(BASE, "PIB e Impostos (SIDRA).xlsx")

# ==============================================================================
# Tabelas de referência
# ==============================================================================

GEO_MAP <- tibble(
  tabela   = 1:33,
  geo      = c(
    "Norte", "Rondônia", "Acre", "Amazonas", "Roraima", "Pará", "Amapá", "Tocantins",
    "Nordeste", "Maranhão", "Piauí", "Ceará", "Rio Grande do Norte", "Paraíba",
    "Pernambuco", "Alagoas", "Sergipe", "Bahia",
    "Sudeste", "Minas Gerais", "Espírito Santo", "Rio de Janeiro", "São Paulo",
    "Sul", "Paraná", "Santa Catarina", "Rio Grande do Sul",
    "Centro-Oeste", "Mato Grosso do Sul", "Mato Grosso", "Goiás", "Distrito Federal",
    "Brasil"
  ),
  geo_tipo = c(
    "regiao", rep("estado", 7),
    "regiao", rep("estado", 9),
    "regiao", rep("estado", 4),
    "regiao", rep("estado", 3),
    "regiao", rep("estado", 4),
    "brasil"
  ),
  regiao   = c(
    rep("Norte",        8),
    rep("Nordeste",    10),
    rep("Sudeste",      5),
    rep("Sul",          4),
    rep("Centro-Oeste", 5),
    "Brasil"
  )
)

ATIV_MAP <- tibble(
  cod       = 1:13,
  atividade = c(
    "total", "agropecuaria", "ind_extrativa", "ind_transformacao",
    "eletricidade_gas_agua", "construcao", "comercio_veiculos",
    "transporte_armazenagem", "informacao_comunicacao",
    "financeiro_seguros", "imobiliaria", "adm_publica", "outros_servicos"
  )
)

# ==============================================================================
# Funções de leitura
# ==============================================================================

# Lê tab01–04 ou SIDRA: wide simples
# L4 = anos (cols 2–23), L5–L37 = dados (33 entidades)
ler_especial_simples <- function(arquivo, variavel, sheet = 1, xlsx = FALSE) {
  fn <- if (xlsx) read_xlsx else read_xls
  df <- fn(arquivo, sheet = sheet, col_names = FALSE, .name_repair = "minimal")

  anos  <- as.numeric(df[4, 2:23])

  df[5:37, 1:23] |>
    set_names(c("geo", paste0("Y", anos))) |>
    mutate(across(everything(), as.character)) |>
    filter(!is.na(geo), !str_starts(geo, "Fonte")) |>
    pivot_longer(-geo, names_to = "ano", names_prefix = "Y", values_to = "valor") |>
    mutate(ano = as.integer(ano), valor = as.numeric(valor), variavel = variavel)
}

# Lê uma aba de tab05–06: wide com linha extra de categoria
# L4 = anos, L5 = label da atividade, L6–L37 = dados (32 entidades)
ler_especial_atividade <- function(arquivo, aba, atividade) {
  df <- read_xls(arquivo, sheet = aba, col_names = FALSE, .name_repair = "minimal")

  anos <- as.numeric(df[4, 2:23])

  df[6:37, 1:23] |>
    set_names(c("geo", paste0("Y", anos))) |>
    mutate(across(everything(), as.character)) |>
    filter(!is.na(geo)) |>
    pivot_longer(-geo, names_to = "ano", names_prefix = "Y", values_to = "valor") |>
    mutate(ano = as.integer(ano), valor = as.numeric(valor), atividade = atividade)
}

# Lê um bloco (VBP / CI / VAB) de uma aba da Conta da Produção
# Colunas fixas: ano | val_ano_ant | idx_volume | val_preco_ant | idx_preco | val_corrente
ler_conta_bloco <- function(tabela_n, aba_n, linhas_dados, bloco_nome) {
  arquivo  <- file.path(CONTA_PROD, paste0("Tabela", tabela_n, ".xls"))
  sheet_idx <- aba_n + 1L  # aba 1 = Sumário; abas 2-14 = atividades 1-13

  df <- read_xls(arquivo, sheet = sheet_idx, col_names = FALSE, .name_repair = "minimal")

  df[linhas_dados, 1:6] |>
    set_names(c("ano", "val_ano_ant", "idx_volume", "val_preco_ant", "idx_preco", "val_corrente")) |>
    mutate(across(everything(), as.numeric)) |>
    mutate(tabela = tabela_n, atividade_cod = aba_n, bloco = bloco_nome)
}

# ==============================================================================
# Leitura: Especiais e SIDRA
# ==============================================================================

message("Lendo Especiais e SIDRA...")

pib_nominal <- ler_especial_simples(
  file.path(ESPECIAIS, "tab01.xls"), "pib_nominal"
)

pib_vol_encadeado <- ler_especial_simples(
  file.path(ESPECIAIS, "tab03.xls"), "pib_vol_encadeado"
)

vab_nominal <- ler_especial_simples(
  file.path(ESPECIAIS, "tab04.xls"), "vab_nominal"
)

# SIDRA está em R$ mil; dividir por 1000 para converter para R$ milhões (= unidade dos Especiais)
impostos_nominal <- ler_especial_simples(
  SIDRA, "impostos_nominal", sheet = 2, xlsx = TRUE
) |>
  mutate(valor = valor / 1000)

# Imputar impostos faltantes (tipicamente 2022–2023) via identidade contábil:
#   Impostos = PIB nominal - VAB nominal
# O SIDRA pode não cobrir os anos mais recentes; para esses pares geo×ano
# ausentes ou com NA, usamos a identidade que é exata nas contas nacionais.
pares_sidra <- impostos_nominal |>
  filter(!is.na(valor)) |>
  select(geo, ano) |>
  distinct()

pares_necessarios <- pib_nominal |>
  select(geo, ano) |>
  distinct()

pares_faltando <- anti_join(pares_necessarios, pares_sidra, by = c("geo", "ano"))

if (nrow(pares_faltando) > 0) {
  anos_imputados <- sort(unique(pares_faltando$ano))
  message("Imputando impostos (PIB - VAB) para ", nrow(pares_faltando),
          " pares geo\u00d7ano sem dados SIDRA. Anos: ",
          paste(anos_imputados, collapse = ", "))

  impostos_imputados <- pares_faltando |>
    left_join(pib_nominal |> select(geo, ano, pib = valor), by = c("geo", "ano")) |>
    left_join(vab_nominal  |> select(geo, ano, vab = valor), by = c("geo", "ano")) |>
    mutate(valor    = pib - vab,
           variavel = "impostos_nominal") |>
    select(geo, ano, valor, variavel)

  impostos_nominal <- bind_rows(
    impostos_nominal |> filter(!is.na(valor)),
    impostos_imputados
  ) |>
    arrange(geo, ano)
} else {
  message("Dados SIDRA cobrem todos os anos disponíveis. Nenhuma imputação necessária.")
}

# tab05: VAB volume encadeado por atividade (13 abas)
message("Lendo tab05 (VAB volume por atividade)...")

vab_vol_ativ <- map2_dfr(
  paste0("Tabela5.", 1:13),
  ATIV_MAP$atividade,
  ~ ler_especial_atividade(file.path(ESPECIAIS, "tab05.xls"), .x, .y)
) |>
  mutate(variavel = paste0("vab_vol_encadeado_", atividade)) |>
  select(-atividade)

# Consolidar especiais em um único tibble tidy
especiais <- bind_rows(
  pib_nominal       |> mutate(atividade = "total"),
  pib_vol_encadeado |> mutate(atividade = "total"),
  vab_nominal       |> mutate(atividade = "total"),
  impostos_nominal  |> mutate(atividade = "total"),
  vab_vol_ativ      |> mutate(atividade = str_remove(variavel, "vab_vol_encadeado_"))
) |>
  left_join(GEO_MAP, by = "geo")

# ==============================================================================
# Leitura: Conta da Produção (33 tabelas × 13 atividades × 3 blocos)
# ==============================================================================

message("Lendo Conta da Produção (33 tabelas × 13 atividades × 3 blocos)...")

blocos <- list(
  list(linhas = 7:28,  nome = "vbp"),
  list(linhas = 35:56, nome = "ci"),
  list(linhas = 63:84, nome = "vab")
)

conta_producao <- map_dfr(1:33, function(tab_n) {
  if (tab_n %% 5 == 0) message("  Tabela ", tab_n, " de 33...")
  map_dfr(1:13, function(ativ_n) {
    map_dfr(blocos, function(b) {
      ler_conta_bloco(tab_n, ativ_n, b$linhas, b$nome)
    })
  })
}) |>
  left_join(GEO_MAP,  by = "tabela") |>
  left_join(ATIV_MAP, by = c("atividade_cod" = "cod")) |>
  select(geo, geo_tipo, regiao, atividade, bloco, ano,
         val_ano_ant, idx_volume, val_preco_ant, idx_preco, val_corrente)

# ==============================================================================
# Salvar
# ==============================================================================

dir.create("dados", showWarnings = FALSE)
saveRDS(especiais,      "dados/especiais.rds")
saveRDS(conta_producao, "dados/conta_producao.rds")
message("Dados salvos em dados/especiais.rds e dados/conta_producao.rds")

# ==============================================================================
# Verificações
# ==============================================================================

message("\n--- Verificações ---")

# Estrutura
message("\nespeciais:")
glimpse(especiais)

message("\nconta_producao:")
glimpse(conta_producao)

# Contagens esperadas
n_esp <- nrow(especiais)
n_cp  <- nrow(conta_producao)
message("\nLinhas em especiais: ", n_esp)
message("Linhas em conta_producao: ", n_cp,
        " (esperado: 33 × 13 × 3 × 22 = ", 33 * 13 * 3 * 22, ")")

# Cobertura temporal
message("\nAnos em especiais: ", paste(range(especiais$ano, na.rm = TRUE), collapse = "–"))
message("Anos em conta_producao: ", paste(range(conta_producao$ano, na.rm = TRUE), collapse = "–"))

# Checagem de NAs no ano 2002 da Conta da Produção
nas_2002 <- conta_producao |>
  filter(ano == 2002) |>
  summarise(
    val_ano_ant_na  = sum(is.na(val_ano_ant)),
    idx_volume_na   = sum(is.na(idx_volume)),
    val_corrente_na = sum(is.na(val_corrente))
  )
message("\nAnos 2002 — NAs esperados nas cols 2–5 (val_ano_ant, idx_volume, etc.):")
print(nas_2002)
message("  (10 NAs em val_corrente = Acre, atividades específicas sem dado em 2002 — limitação do IBGE)")

# Comparação PIB nominal: tab01 vs SIDRA
pib_tab01 <- pib_nominal |> filter(geo == "Brasil", ano == 2023) |> pull(valor)
pib_sidra <- ler_especial_simples(SIDRA, "pib_nominal_sidra", sheet = 1, xlsx = TRUE) |>
  filter(geo == "Brasil", ano == 2023) |> pull(valor)
message("\nPIB Brasil 2023 — tab01: ", round(pib_tab01),
        " | SIDRA: ", round(pib_sidra),
        " | Razão: ", round(pib_tab01 / pib_sidra, 4),
        " (esperado ≈ 1 se mesma unidade)")
