# Baseline da Reforma

## Finalidade

Registrar o ponto de restauração da reforma antes de qualquer alteração estrutural no pipeline analítico.

Este documento corresponde ao **Bloco 1 - Preservação e baseline** do `plano_reforma.md`.

---

## Referência Git

- **Commit de referência:** `cb2b4b675eefc7cd9223211897de14e13e3377fa`
- **Tag de restauração:** `v1.0-painel-atual`
- **Branch de trabalho da reforma:** `reforma-pipeline-univariado`

### Comandos de restauração

```bash
git fetch --all --tags
git checkout v1.0-painel-atual
```

Para voltar à branch de trabalho da reforma:

```bash
git checkout reforma-pipeline-univariado
```

---

## Baseline funcional preservado

No ponto de referência marcado pela tag `v1.0-painel-atual`, o projeto apresenta:

- pipeline analítico com scripts `R/01` a `R/06`;
- painel Quarto + shinylive publicado via GitHub Pages;
- cobertura de 27 UFs, 5 regiões e Brasil;
- horizonte projetado de 2024 a 2031;
- reconciliação top-down;
- exportação dos CSVs versionados em `painel/data/`.

---

## CSVs preservados do painel

Os arquivos abaixo estão versionados no repositório e preservados pela tag.

| Arquivo | Linhas | SHA-256 |
|---------|--------|---------|
| `painel/data/serie_principal.csv` | 4.950 | `43B55512B8906F0D19D931CD84EE624540DE55985592DCEE2128D8D8C9C8023D` |
| `painel/data/vab_macrossetor.csv` | 3.960 | `474963F42920A04A8863DFB0821FDEBDC53DBEA1900E8E3E59629BDF4666058B` |
| `painel/data/vab_atividade.csv` | 11.880 | `6D4D9702090D410623D709B7F163B77D81B72C6A6E359AA1891E7A410A6832C0` |

Esses hashes servem como referência para validar que a restauração do baseline corresponde exatamente ao estado preservado.

---

## Outputs de referência

Como `dados/` e `output/` não são versionados, a referência oficial desta reforma passa a ser:

1. a tag `v1.0-painel-atual`;
2. os CSVs de `painel/data/` preservados no Git;
3. a documentação vigente em `README.md`, `painel/metodologia.html` e `progresso.md`.

Outputs esperados nessa referência:

- `painel/data/serie_principal.csv`
- `painel/data/vab_macrossetor.csv`
- `painel/data/vab_atividade.csv`
- `painel/metodologia.html`
- painel publicado no GitHub Pages

---

## Critério de conclusão do Bloco 1

O Bloco 1 é considerado concluído quando:

- existe uma branch dedicada à reforma;
- existe uma tag de restauração da versão atual;
- o baseline atual está documentado;
- os CSVs versionados do painel estão inventariados;
- a restauração do estado anterior pode ser feita de forma simples e verificável.
