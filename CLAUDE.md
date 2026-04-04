# Instrucoes para Claude - Projeto Projecoes PIBs Estaduais

## Regra obrigatoria apos qualquer alteracao no projeto

**A cada nova alteracao realizada neste projeto, voce deve:**

1. **Atualizar `progresso.md`** - registre o que foi feito, sob qual etapa pertence, quais arquivos foram criados ou modificados, e os outputs gerados (com numero de linhas quando aplicavel). Siga o padrao de formatacao ja estabelecido no arquivo.

2. **Atualizar `checklist_reforma.md` quando a alteracao fizer parte da reforma** - marque os itens concluidos e mantenha o status dos blocos coerente com o andamento real.

3. **Fazer commit** com mensagem descritiva em portugues, no formato:
   ```
   <verbo no imperativo>: <descricao do que foi feito>
   ```
   Exemplos: `Adiciona aba Selecao_Modelos ao output Excel`,
   `Corrige calculo do deflator projetado`.

4. **Fazer push** para o repositorio remoto:
   `https://github.com/yuricesarsilva/painel_projecao_pib_estados.git`

   Comando:
   - `git push origin main` quando estiver trabalhando na branch principal
   - `git push origin <nome-da-branch>` quando a etapa estiver sendo executada em branch dedicada

Isso garante que o repositorio GitHub reflita sempre o estado atual do projeto.

---

## Contexto do projeto

- **Objetivo:** projetar PIB nominal, VAB, impostos, deflatores e crescimento real para 27 UFs + 5 regioes + Brasil (2024-2031), com restricoes de agregacao contabil.
- **Pipeline:** `run_all.R` executa em sequencia `R/01` a `R/06`.
- **Horizonte historico:** 2002-2023 (IBGE Contas Regionais).
- **Dados brutos em `base_bruta/`** - excluidos do git via `.gitignore`.
- **Dados processados em `dados/`** - excluidos do git.
- **Outputs em `output/`** - excluidos do git.
- Scripts em `R/` e arquivos `.md` sao versionados.

---

## Estrutura dos scripts

| Script | Funcao |
|--------|--------|
| `R/01_leitura_dados.R` | Le todos os dados brutos e salva `dados/*.rds` |
| `R/02_consistencia.R` | Verifica identidades contabeis nos dados historicos |
| `R/03_projecao.R` | Modela series e projeta 2024-2031 |
| `R/04_reconciliacao.R` | Impoe restricoes de agregacao (benchmarking top-down) |
| `R/05_output.R` | Gera Excel e graficos PNG |
| `R/06_exportar_painel.R` | Exporta CSVs para o painel interativo |

---

## Padrao de commit

Sempre ao final de uma sessao de alteracoes, ou apos completar uma etapa:

```bash
git add R/ progresso.md checklist_reforma.md CLAUDE.md
git commit -m "mensagem descritiva"
git push origin <branch-atual>
```

Nunca adicione `base_bruta/`, `dados/` ou `output/` ao git.
