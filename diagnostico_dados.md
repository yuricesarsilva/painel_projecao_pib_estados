# Diagnóstico dos Dados — Projeções PIBs Estaduais

Inspeção realizada em 2026-03-31. Dados do IBGE Contas Regionais 2002–2023.

## Estrutura dos arquivos

| Arquivo | Conteúdo | Cobertura geográfica | Cobertura temporal |
|---------|----------|----------------------|--------------------|
| `Especiais/tab01.xls` | PIB nominal | 27 UFs + 5 regiões + Brasil | 2002–2023 |
| `Especiais/tab02.xls` | Participação % no PIB | idem | idem |
| `Especiais/tab03.xls` | Série encadeada do volume do PIB (índice, base 2002=100) | idem | idem |
| `Especiais/tab04.xls` | VAB nominal total | idem | idem |
| `Especiais/tab05.xls` | Série encadeada do volume do VAB por atividade (13 abas) | idem | idem |
| `Especiais/tab06.xls` | Participação % no VAB por atividade (13 abas) | idem | idem |
| `Especiais/tab07.xls` | Participação % das atividades no VAB por UF (33 abas) | idem | idem |
| `Conta_da_Producao/Tabela{1..33}.xls` | VBP, CI e VAB por atividade (nominal + índice de volume + índice de preço) | 33 unidades (ver tabela abaixo) | 2002–2023 |
| `PIB e Impostos (SIDRA).xlsx` | PIB nominal + Impostos líquidos de subsídios nominais | 27 UFs + 5 regiões + Brasil | 2002–2023 |

## Estrutura interna das Tabelas de Conta da Produção

Cada arquivo `TabelaN.xls` possui abas: `Sumário`, `TabelaN.1` a `TabelaN.13`.

Cada aba de atividade contém **três blocos** (Valor Bruto da Produção, Consumo Intermediário, Valor Adicionado Bruto), cada um com **6 colunas por ano**:

| Coluna | Descrição |
|--------|-----------|
| ANO | Ano de referência |
| VALOR DO ANO ANTERIOR (1 000 000 R$) | Valor nominal do ano t-1 |
| ÍNDICE DE VOLUME | Índice de volume (t / t-1) |
| VALOR A PREÇOS DO ANO ANTERIOR (1 000 000 R$) | Valor do ano t a preços de t-1 |
| ÍNDICE DE PREÇO | Índice de preço (deflator) (t / t-1) |
| VALOR A PREÇO CORRENTE (1 000 000 R$) | Valor nominal do ano t |

> O ano base de referência é 2010. O primeiro ano (2002) só possui valor corrente; os índices começam em 2003.

## Correspondência Tabela → Unidade geográfica

| Tabela | Unidade | Tabela | Unidade |
|--------|---------|--------|---------|
| 1 | Região Norte | 18 | Bahia |
| 2 | Rondônia | 19 | Região Sudeste |
| 3 | Acre | 20 | Minas Gerais |
| 4 | Amazonas | 21 | Espírito Santo |
| 5 | Roraima | 22 | Rio de Janeiro |
| 6 | Pará | 23 | São Paulo |
| 7 | Amapá | 24 | Região Sul |
| 8 | Tocantins | 25 | Paraná |
| 9 | Região Nordeste | 26 | Santa Catarina |
| 10 | Maranhão | 27 | Rio Grande do Sul |
| 11 | Piauí | 28 | Região Centro-Oeste |
| 12 | Ceará | 29 | Mato Grosso do Sul |
| 13 | Rio Grande do Norte | 30 | Mato Grosso |
| 14 | Paraíba | 31 | Goiás |
| 15 | Pernambuco | 32 | Distrito Federal |
| 16 | Alagoas | 33 | Brasil |
| 17 | Sergipe | | |

## Disponibilidade das variáveis do projeto

| Variável necessária | Disponível? | Fonte | Forma |
|---------------------|-------------|-------|-------|
| PIB nominal | ✅ | `tab01.xls` e SIDRA aba "PIB" | Direto |
| VAB nominal total | ✅ | `tab04.xls` e Conta da Produção (col. "VALOR A PREÇO CORRENTE") | Direto |
| VAB nominal por atividade (13 ativ.) | ✅ | Conta da Produção, aba N.1–N.13, bloco VAB | Direto |
| Impostos líquidos de subsídios nominais | ✅ | SIDRA aba "Impostos, líquidos de subsíd..." | Direto |
| Índice de preço (deflator) do VAB por atividade | ✅ | Conta da Produção col. "ÍNDICE DE PREÇO" | Direto |
| Deflator implícito do PIB | ✅ | Derivado: `tab01` / `tab03` (nominal / volume) | Calculado |
| Taxa de crescimento do PIB real | ✅ | Derivado de `tab03` (série encadeada volume) | Calculado |
| VAB 4 macrossetores | ✅ | Soma de atividades na Conta da Produção | Agregação |

### Macrossetores → atividades de origem

| Macrossetor | Abas da Conta da Produção |
|-------------|--------------------------|
| Agropecuária | N.2 |
| Indústria | N.3 + N.4 + N.5 + N.6 |
| Administração Pública | N.12 |
| Serviços (excl. Adm. Pública) | N.7 + N.8 + N.9 + N.10 + N.11 + N.13 |

## Notas importantes

- **2022–2023**: O SIDRA (Tabela 5938) informa que para esses anos foram publicados apenas PIB e impostos. Porém, os arquivos `Conta_da_Producao_2002_2023_xls/` contêm dados completos (VAB por atividade, volume e preço) até 2023. Os dados de 2022–2023 estão sujeitos a revisão nas próximas publicações do IBGE.
- **Unidade monetária**: valores em R$ milhões (1 000 000 R$).
- **Ano de referência do índice encadeado**: 2010.
- **Identidade contábil verificável**: PIB = VAB + Impostos líquidos de subsídios (para cada UF/região/Brasil e cada ano).

## Conclusão

**Os dados são totalmente suficientes para o projeto.** Nenhuma lacuna crítica identificada. Todas as variáveis requeridas estão disponíveis com cobertura completa de 2002–2023 para os 27 estados, 5 regiões e Brasil.
