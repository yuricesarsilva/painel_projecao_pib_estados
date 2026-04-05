# Plano do Projeto: Projeções dos PIBs Estaduais do Brasil

## Objetivo

Projetar variáveis de PIB para todos os **27 estados + 5 regiões + Brasil**, respeitando restrições de agregação contábil.

## Restrições de Agregação (obrigatórias)

1. **Soma dos PIBs estaduais = PIB Brasil**
2. **Soma dos PIBs dos estados de cada região = PIB da respectiva região**
3. **PIB nominal = VAB nominal + Impostos líquidos de subsídios nominais** (para cada unidade)

## Variáveis a Projetar

Para cada estado, região e Brasil:

| # | Variável | Desagregação |
|---|----------|-------------|
| 1 | PIB nominal | — |
| 2 | VAB nominal | Total + por atividade econômica (13 atividades) |
| 3 | Impostos líquidos de subsídios nominais | — |
| 4 | Índice de preço (deflator implícito) | Total + por atividade econômica |
| 5 | Taxa de crescimento do PIB real | — |
| 6 | VAB por 4 macrossetores | Ver seção abaixo |

### Macrossetores (item 6)

| Macrossetor | Atividades (tabelas de origem) |
|-------------|-------------------------------|
| Agropecuária | Tab. 1.2 |
| Indústria | Tab. 1.3 + 1.4 + 1.5 + 1.6 |
| Administração Pública | Tab. 1.12 |
| Serviços (excl. Adm. Pública) | Tab. 1.7 + 1.8 + 1.9 + 1.10 + 1.11 + 1.13 |

### Atividades econômicas (13 atividades do IBGE)

| Cód. | Atividade |
|------|-----------|
| 1.1 | Total das Atividades |
| 1.2 | Agropecuária |
| 1.3 | Indústrias extrativas |
| 1.4 | Indústrias de transformação |
| 1.5 | Eletricidade e gás, água, esgoto, gestão de resíduos e descontaminação |
| 1.6 | Construção |
| 1.7 | Comércio e reparação de veículos automotores e motocicletas |
| 1.8 | Transporte, armazenagem e correio |
| 1.9 | Informação e comunicação |
| 1.10 | Atividades financeiras, de seguros e serviços relacionados |
| 1.11 | Atividades imobiliárias |
| 1.12 | Administração, defesa, educação e saúde públicas e seguridade social |
| 1.13 | Outros serviços |

## Fonte de Dados (base_bruta/)

### Conta_da_Producao_2002_2023_xls/

Tabelas 1–33, estrutura: uma tabela por unidade geográfica × 13 subtabelas por atividade.

| Tabela | Unidade Geográfica |
|--------|--------------------|
| 1 | Região Norte |
| 2 | Rondônia |
| 3 | Acre |
| 4 | Amazonas |
| 5 | Roraima |
| 6 | Pará |
| 7 | Amapá |
| 8 | Tocantins |
| 9 | Região Nordeste |
| 10 | Maranhão |
| 11 | Piauí |
| 12 | Ceará |
| 13 | Rio Grande do Norte |
| 14 | Paraíba |
| 15 | Pernambuco |
| 16 | Alagoas |
| 17 | Sergipe |
| 18 | Bahia |
| 19 | Região Sudeste |
| 20 | Minas Gerais |
| 21 | Espírito Santo |
| 22 | Rio de Janeiro |
| 23 | São Paulo |
| 24 | Região Sul |
| 25 | Paraná |
| 26 | Santa Catarina |
| 27 | Rio Grande do Sul |
| 28 | Região Centro-Oeste |
| 29 | Mato Grosso do Sul |
| 30 | Mato Grosso |
| 31 | Goiás |
| 32 | Distrito Federal |
| 33 | Brasil |

Cada tabela N contém os subtópicos N.1 (Total) a N.13 (Outros serviços) com:
- Valor da Produção, Consumo Intermediário, VAB (a preços básicos), em valores correntes e índices encadeados de volume.

### Especiais_2002_2023_xls/

| Tabela | Conteúdo |
|--------|----------|
| tab01 | PIB nominal — Brasil, Regiões e UFs |
| tab02 | Participação das UFs no PIB |
| tab03 | Série encadeada do volume do PIB |
| tab04 | VAB nominal — Brasil, Regiões e UFs |
| tab05 | Série encadeada do volume do VAB por atividade |
| tab06 | Participação das UFs no VAB por atividade |
| tab07 | Participação das atividades no VAB por UF |

### PIB e Impostos (SIDRA).xlsx

Dados de impostos líquidos de subsídios por UF (fonte: SIDRA/IBGE).

## Estrutura do Projeto (estado atual)

```
Projeções/
├── plano_projeto.md              ← documento de escopo original
├── projeto_projecao_pib.Rproj
├── renv.lock                     ← ambiente reproduzível (renv)
├── base_bruta/                   ← dados originais IBGE (não versionados)
├── dados/                        ← dados processados intermediários (não versionados)
├── output/                       ← tabelas e gráficos gerados (não versionados)
│   ├── tabelas/
│   ├── graficos/
│   └── logs/
├── R/
│   ├── config.R              ← parâmetros centrais (anos, horizonte, seed, tolerâncias)
│   ├── utils_cache.R         ← cache com invalidação automática por hash
│   ├── utils_logging.R       ← logging estruturado por execução
│   ├── run_all.R             ← orquestra o pipeline completo
│   ├── 01_leitura_dados.R    ← importa e estrutura dados brutos do IBGE
│   ├── 02_consistencia.R     ← verifica identidades contábeis (barreira de execução)
│   ├── 03_projecao.R         ← CV two-stage + 7 modelos + projeção ~1.089 séries
│   ├── 04_reconciliacao.R    ← benchmarking top-down (BR → região → UF)
│   ├── 05_output.R           ← tabelas Excel e gráficos PNG
│   └── 06_exportar_painel.R  ← exporta CSVs para o painel interativo
└── painel/
    ├── painel.qmd            ← Quarto Dashboard + shinylive (GitHub Pages)
    ├── metodologia.html      ← nota metodológica pública
    └── data/                 ← CSVs versionados consumidos pelo painel
```

## Abordagem Metodológica (referência)

1. **Projeção das variáveis reais** (taxa de crescimento do PIB real e VAB real por setor): modelos univariados ou multivariados por UF.
2. **Projeção dos deflatores** (índice de preço por setor/UF): trajetória de preços consistente com cenário macroeconômico nacional.
3. **Cálculo do nominal**: VAB nominal = VAB real × deflator; PIB nominal = VAB nominal + impostos nominais.
4. **Reconciliação**: após projeção individual, aplicar método de reconciliação (ex.: benchmarking proporcional, método de Denton-Cholette ou otimização com restrições lineares) para garantir que:
   - Soma estadual = regional = nacional
   - PIB = VAB + impostos
5. **Validação**: checar identidades contábeis ex-post em cada ano projetado.

## Horizonte de Projeção

A definir. Dados históricos disponíveis: 2002–2023.
