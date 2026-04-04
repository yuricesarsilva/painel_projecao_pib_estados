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

- [ ] Adotar `renv`
- [ ] Criar `renv.lock`
- [ ] Remover `install.packages()` do pipeline analítico
- [ ] Ajustar o workflow para restaurar o ambiente
- [ ] Criar `R/config.R`
- [ ] Centralizar anos, horizonte, seed e tolerâncias

### Reprodutibilidade e cache

- [ ] Definir `SEED_GLOBAL` no pipeline
- [ ] Adicionar logging estruturado da execução
- [ ] Registrar commit hash, timestamp e hash dos insumos
- [ ] Criar utilitário de cache com invalidação automática
- [ ] Salvar metadados do cache junto da seleção de modelos
- [ ] Validar reutilização correta do cache

---

## Bloco 3 - QA e governança analítica

- [ ] Tornar `R/02_consistencia.R` uma barreira de execução
- [ ] Classificar checagens em erro fatal e warning monitorado
- [ ] Fazer `R/run_all.R` interromper o pipeline quando o QA falhar
- [ ] Definir horizonte operacional
- [ ] Definir horizonte exploratório
- [ ] Refletir essa distinção no README
- [ ] Refletir essa distinção na metodologia
- [ ] Refletir essa distinção no painel

---

## Bloco 4 - Reforma estatística do baseline univariado

### Validação cruzada e seleção

- [ ] Redesenhar o CV para múltiplos horizontes
- [ ] Definir pesos dos horizontes do CV
- [ ] Salvar métricas por horizonte e por modelo
- [ ] Alinhar a triagem do CV com a estimação final
- [ ] Reavaliar finalistas com a especificação final

### Família de modelos

- [ ] Definir a família principal de modelos do baseline
- [ ] Mover modelos experimentais para trilha separada ou removê-los do baseline
- [ ] Atualizar README com a nova família de modelos
- [ ] Atualizar metodologia com a nova família de modelos

### Robustez de execução

- [ ] Registrar warnings e erros por série/modelo
- [ ] Registrar fallback por série
- [ ] Definir limiar máximo aceitável de fallback
- [ ] Fazer o pipeline falhar se a degradação exceder o limite

---

## Bloco 5 - Transparência, automação e documentação

### Diagnóstico analítico

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

- [ ] Atualizar `README.md`
- [ ] Atualizar `painel/metodologia.html`
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
- [ ] Bloco 2 concluído
- [ ] Bloco 3 concluído
- [ ] Bloco 4 concluído
- [ ] Bloco 5 concluído
