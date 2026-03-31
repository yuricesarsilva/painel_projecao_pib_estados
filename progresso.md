# Progresso do Projeto — Projeções PIBs Estaduais

## Etapa 0 — Planejamento e configuração

**O que foi feito:**
- Definido o escopo do projeto: projetar PIB nominal, VAB nominal (total e por atividade), impostos líquidos de subsídios, deflatores, taxa de crescimento real e VAB por 4 macrossetores para 27 UFs + 5 regiões + Brasil, com restrições de agregação contábil obrigatórias.
- Criado `plano_projeto.md` com objetivo, variáveis, macrossetores, fontes de dados e estrutura proposta de scripts.
- Criado repositório GitHub `yuricesarsilva/relatorio_projecao_pib_estados` (privado).
- Configurado git no diretório do projeto com `.gitignore` excluindo `base_bruta/`, `dados/` e `output/`.

**Arquivos criados:** `plano_projeto.md`, `.gitignore`

---

## Etapa 1 — Inspeção e diagnóstico dos dados

**O que foi feito:**
- Inspecionados todos os arquivos brutos em `base_bruta/` usando R (`readxl`).
- Mapeada a estrutura exata de cada tipo de arquivo (linhas de cabeçalho, linhas de dados, colunas).
- Confirmado que os dados são suficientes para todas as variáveis do projeto.
- Identificado e documentado: unidade monetária (R$ milhões nos Especiais, R$ mil no SIDRA), ano de referência do índice encadeado (2010), cobertura 2002–2023.
- Criado `diagnostico_dados.md` com estrutura completa, disponibilidade por variável e notas.

**Principais achados:**
- Conta da Produção: 33 arquivos × 13 atividades × 3 blocos (VBP, CI, VAB) × 6 colunas (ano, val_ano_ant, idx_volume, val_preco_ant, idx_preco, val_corrente).
- `Tabela19.xls` (Região Sudeste) tem bug nos nomes das abas — usa `Tabela1.x` em vez de `Tabela19.x`.
- SIDRA em R$ mil; Especiais em R$ milhões — requer conversão.
- Acre tem 10 NAs em `val_corrente` para 2002 em atividades de serviços — limitação do IBGE original.

**Arquivos criados:** `diagnostico_dados.md`

---

## Etapa 2 — Leitura e estruturação dos dados (`R/01_leitura_dados.R`)

**O que foi feito:**
- Criado script R que lê todas as fontes brutas e salva dois `.rds` em formato tidy em `dados/`.
- Implementadas 3 funções de leitura reutilizáveis:
  - `ler_especial_simples()` — para tab01–04 e SIDRA (wide, 33 entidades).
  - `ler_especial_atividade()` — para tab05 (wide com linha extra de categoria, 32 entidades).
  - `ler_conta_bloco()` — para um bloco (VBP/CI/VAB) da Conta da Produção, usando índice posicional de aba (contorna o bug do Tabela19.xls).
- Tabelas de referência `GEO_MAP` e `ATIV_MAP` embutidas no script.
- Correção de unidades: SIDRA dividido por 1.000 para ficar em R$ milhões.
- Verificações embutidas ao final: contagem de linhas, cobertura temporal, NAs esperados, comparação de unidades tab01 vs SIDRA.

**Outputs gerados:**

| Arquivo | Colunas | Linhas |
|---------|---------|--------|
| `dados/especiais.rds` | geo, geo_tipo, regiao, ano, variavel, atividade, valor | 12.056 |
| `dados/conta_producao.rds` | geo, geo_tipo, regiao, atividade, bloco, ano, val_ano_ant, idx_volume, val_preco_ant, idx_preco, val_corrente | 28.314 |

**Arquivos criados:** `R/01_leitura_dados.R`

---

---

## Etapa 3 — Verificação de consistência contábil (`R/02_consistencia.R`)

**O que foi feito:**
- Criado script que verifica 4 identidades contábeis nos dados históricos (2002–2023).
- Resultados salvos em `dados/consistencia.rds`.

**Resultados:**

| Checagem | Desvio máximo | Resultado |
|----------|--------------|-----------|
| PIB = VAB + Impostos | ~0,000002% | ✅ Satisfeita (arredondamento numérico) |
| Soma dos estados = PIB da região | ~10⁻¹³% | ✅ Satisfeita (ponto flutuante) |
| Soma das regiões = PIB Brasil | ~10⁻¹³% | ✅ Satisfeita (ponto flutuante) |
| Soma das atividades = VAB total | -64% em Acre 2002 | ⚠️ Único caso — NAs já conhecidos do IBGE |

**Nota:** O desvio de Acre 2002 é causado pelos 10 NAs em `val_corrente` identificados na Etapa 1. A soma das atividades fica incompleta, mas o total do IBGE está correto. Não é erro do pipeline.

**Arquivos criados:** `R/02_consistencia.R`

---

## Próximas etapas

- [x] `R/01_leitura_dados.R` — leitura e estruturação dos dados brutos
- [x] `R/02_consistencia.R` — verificar identidades contábeis nos dados históricos
- [ ] `R/03_projecao.R` — modelos de projeção por variável e setor
- [ ] `R/04_reconciliacao.R` — garantir restrições de agregação nas projeções
- [ ] `R/05_output.R` — gerar tabelas e gráficos de resultado
