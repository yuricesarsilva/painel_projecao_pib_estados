# Checklist da Reforma do Projeto

## Como usar

- Marcar `[x]` quando a etapa estiver concluída.
- Manter `[ ]` enquanto a etapa estiver pendente.
- Atualizar este arquivo sempre que um item relevante da reforma for concluído.
- Usar este checklist junto com `plano_reforma.md` e `progresso.md`.

---

## Bloco 1 - Preservação e baseline

- [x] Criar branch de trabalho da reforma
- [x] Criar tag da versão atual
- [x] Registrar quais outputs atuais serão a referência da reforma
- [x] Preservar os CSVs atuais de `painel/data/`
- [x] Confirmar que a versão atual pode ser restaurada integralmente

---

## Bloco 2 - Infraestrutura obrigatória

### Ambiente e configuração

- [x] Adotar `renv`
- [x] Criar `renv.lock`
- [x] Remover `install.packages()` do pipeline analítico
- [x] Ajustar o workflow para restaurar o ambiente
- [x] Criar `R/config.R`
- [x] Centralizar anos, horizonte, seed e tolerâncias

### Reprodutibilidade e cache

- [x] Definir `SEED_GLOBAL` no pipeline
- [x] Adicionar logging estruturado da execução
- [x] Registrar commit hash, timestamp e hash dos insumos
- [x] Criar utilitário de cache com invalidação automática
- [x] Salvar metadados do cache junto da seleção de modelos
- [x] Validar reutilização correta do cache

---

## Bloco 3 - QA e governança analítica

> Observação de estágio atual: a distinção operacional/exploratória foi implementada nesta etapa da reforma, mas o produto público do painel foi posteriormente simplificado para `h=3` (`2024–2026`), mantendo o horizonte longo apenas nas saídas técnicas.

- [x] Tornar `R/02_consistencia.R` uma barreira de execução
- [x] Classificar checagens em erro fatal e warning monitorado
- [x] Fazer `R/run_all.R` interromper o pipeline quando o QA falhar
- [x] Definir horizonte operacional
- [x] Definir horizonte exploratório
- [x] Refletir essa distinção no README
- [x] Refletir essa distinção na metodologia
- [x] Refletir essa distinção no painel

---

## Bloco 4 - Reforma estatística do baseline univariado

### Validação cruzada e seleção

- [x] Redesenhar o CV para múltiplos horizontes
- [x] Definir pesos dos horizontes do CV
- [x] Salvar métricas por horizonte e por modelo
- [x] Alinhar a triagem do CV com a estimação final
- [x] Reavaliar finalistas com a especificação final

### Família de modelos

- [x] Definir a família principal de modelos do baseline
- [x] Mover modelos experimentais para trilha separada ou removê-los do baseline
- [x] Atualizar README com a nova família de modelos
- [x] Atualizar metodologia com a nova família de modelos

### Robustez de execução

- [x] Registrar warnings e erros por série/modelo
- [x] Registrar fallback por série
- [x] Definir limiar máximo aceitável de fallback
- [x] Fazer o pipeline falhar se a degradação exceder o limite

---

## Bloco 5 - Transparência, automação e documentação

### Diagnóstico analítico

- [x] Permitir preview local do painel com dados de `painel/data`
- [x] Garantir que o Quarto em `painel/` use o `renv` do projeto
- [x] Criar scripts locais para preview e render do painel
- [x] Criar script R para abrir o preview do painel
- [ ] Exportar CSV de diagnóstico dos modelos
- [ ] Incluir modelo vencedor no diagnóstico
- [ ] Incluir métricas principais no diagnóstico
- [ ] Incluir ranking dos modelos no diagnóstico
- [ ] Incluir status de fallback no diagnóstico
- [ ] Expor diagnóstico no painel

### CI/CD

- [ ] Criar workflow de rebuild analítico
- [ ] Separar workflow de deploy do painel
- [ ] Condicionar publicação a base analítica válida

### Documentação

- [x] Atualizar `README.md`
- [x] Atualizar `painel/metodologia.html`
- [ ] Criar `docs/arquitetura.md`
- [ ] Criar `docs/qa.md`
- [ ] Criar `docs/modelagem.md`

---

## Fase futura - Fora do escopo atual

- [ ] Criar camada `xreg`
- [ ] Estruturar base de indicadores externos
- [ ] Testar reconciliação alternativa (`MinT` ou `middle-out`)
- [ ] Revisar bandas de incerteza com bootstrap ou simulação

---

## Status geral

- [x] Bloco 1 concluído
- [x] Bloco 2 concluído
- [x] Bloco 3 concluído
- [x] Bloco 4 concluído
- [ ] Bloco 5 concluído
