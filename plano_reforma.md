# Plano de Reforma do Projeto

## Objetivo

Reformar o projeto de projeção dos PIBs estaduais em camadas, priorizando:

1. confiabilidade operacional;
2. reprodutibilidade;
3. coerção de qualidade;
4. transparência analítica;
5. evolução metodológica do pipeline **univariado**.

Esta rodada **não inclui modelos com regressoras exógenas (`xreg`)**. A frente `xreg` fica explicitamente adiada para uma versão metodológica futura, quando houver séries auxiliares adequadas.

---

## Princípios da reforma

- Não começar pelo painel.
- Não ampliar escopo metodológico antes de estabilizar o pipeline atual.
- Manter a versão atual recuperável antes de qualquer refatoração relevante.
- Tratar como prioridade o que reduz risco de publicação incorreta.
- Separar claramente:
  - **reforma do baseline atual**;
  - **pesquisa metodológica futura**.

---

## Escopo desta rodada

### Incluído

- congelamento da versão atual;
- governança do ambiente;
- centralização de configuração;
- checagens bloqueantes;
- cache com invalidação automática;
- semente global e logging;
- revisão da validação cruzada do pipeline univariado;
- alinhamento entre seleção e projeção final;
- racionalização da família de modelos univariados;
- distinção entre horizonte operacional e exploratório;
- exportação de diagnósticos para o painel;
- separação entre rebuild analítico e deploy;
- atualização da documentação técnica.

### Explicitamente adiado

- modelos com `xreg`;
- nova base de indicadores externos;
- reconciliação alternativa como entrega obrigatória;
- revisão profunda das bandas de incerteza baseada em simulação;
- expansão do painel por conveniência visual antes da camada analítica estar estável.

---

## Ordem de execução recomendada

## Bloco 1 - Preservação e baseline

### 1. Congelar a versão atual

**Objetivo**
Criar um ponto de restauração íntegro antes da reforma.

**Ações**
- criar branch de trabalho;
- criar tag da versão atual;
- registrar quais outputs atuais são a referência;
- preservar os CSVs atuais de `painel/data/`.

**Critério de conclusão**
A versão atual pode ser restaurada integralmente por tag/branch.

---

## Bloco 2 - Infraestrutura obrigatória

### 2. Adotar `renv` e remover instalação em tempo de execução

**Arquivos principais**
- `renv.lock`
- `R/03_projecao.R`
- `.github/workflows/publish-painel.yml`

**Ações**
- inicializar `renv`;
- remover `install.packages()` do pipeline;
- fazer o ambiente falhar de forma explícita quando estiver incompleto;
- migrar o CI para restauração do ambiente.

**Critério de conclusão**
Uma máquina limpa recompõe o ambiente com `renv::restore()`.

### 3. Criar configuração central do projeto

**Arquivos principais**
- `R/config.R`
- `R/run_all.R`
- `R/02_consistencia.R`
- `R/03_projecao.R`
- `R/04_reconciliacao.R`

**Ações**
- centralizar anos, horizonte, seed, tolerâncias, flags e parâmetros do CV;
- remover constantes duplicadas dos scripts.

**Critério de conclusão**
Horizonte, tolerâncias e parâmetros críticos passam a ser alterados em um único arquivo.

### 4. Adicionar semente global e logging estruturado

**Arquivos principais**
- `R/run_all.R`
- `R/03_projecao.R`
- `output/logs/` ou `logs/`

**Ações**
- definir `set.seed(SEED_GLOBAL)` no início do pipeline;
- registrar timestamp, seed, hash dos insumos, commit e contagem de falhas/fallbacks;
- registrar log por execução e por série quando houver falha relevante.

**Critério de conclusão**
Execuções repetidas com a mesma base e ambiente geram resultados reproduzíveis e rastreáveis.

### 5. Trocar cache manual por invalidação automática

**Arquivos principais**
- `R/03_projecao.R`
- `R/utils_cache.R`

**Ações**
- calcular hash dos insumos da etapa de seleção;
- salvar metadados junto do cache;
- reutilizar cache só quando a assinatura continuar válida.

**Critério de conclusão**
O pipeline nunca mais depende de exclusão manual de cache.

---

## Bloco 3 - QA e governança analítica

### 6. Tornar a consistência uma barreira de execução

**Arquivos principais**
- `R/02_consistencia.R`
- `R/run_all.R`

**Ações**
- classificar verificações em erro fatal e warning monitorado;
- produzir um objeto de status de QA;
- interromper o pipeline quando a base violar regras estruturais.

**Critério de conclusão**
O pipeline deixa de avançar quando as identidades essenciais falham.

### 7. Separar horizonte operacional de horizonte exploratório

**Arquivos principais**
- `R/config.R`
- `R/06_exportar_painel.R`
- `painel/painel.qmd`
- `painel/metodologia.html`
- `README.md`

**Ações**
- tratar 2024-2026 ou 2024-2027 como horizonte principal;
- tratar 2028-2031 como horizonte exploratório;
- refletir essa distinção no painel e na documentação.

**Nota de compatibilidade com o estado atual**
- nesta rodada, a solução pública acabou sendo ainda mais conservadora: o painel passou a exibir apenas `2024–2026 (h=3)`;
- a extensão do horizonte até `2031` permanece apenas nas saídas técnicas complementares.

**Critério de conclusão**
O usuário consegue distinguir imediatamente o trecho mais confiável do horizonte mais frágil.

---

## Bloco 4 - Reforma estatística do baseline univariado

### 8. Redesenhar o CV para múltiplos horizontes

**Arquivos principais**
- `R/03_projecao.R`

**Ações**
- manter expanding window;
- avaliar múltiplos horizontes;
- criar métrica agregada ponderada;
- salvar métricas por horizonte e por modelo.

**Critério de conclusão**
O modelo vencedor passa a refletir o uso real do painel, e não apenas previsão de um passo.

### 9. Alinhar seleção e estimação final

**Arquivos principais**
- `R/03_projecao.R`

**Ações**
- usar triagem rápida apenas como peneira;
- reavaliar finalistas com a mesma especificação da projeção final;
- tornar coerente a lógica entre CV e forecast final.

**Critério de conclusão**
O modelo escolhido e o modelo usado para projetar deixam de divergir em especificação.

### 10. Enxugar a família de modelos

**Arquivos principais**
- `R/03_projecao.R`
- `README.md`
- `painel/metodologia.html`

**Direção recomendada**
- manter núcleo principal com `rw`, `arima`, `ets`, `theta` e `ssm`;
- mover `nnar`, `prophet` e `sarima` para trilha experimental ou removê-los do baseline;
- justificar qualquer permanência por evidência agregada de backtest.

**Critério de conclusão**
O baseline fica mais parcimonioso, auditável e defensável para séries anuais curtas.

### 11. Endurecer o tratamento de falhas, warnings e fallback

**Arquivos principais**
- `R/03_projecao.R`

**Ações**
- parar de silenciar problemas relevantes;
- registrar warnings e erros por série/modelo;
- estabelecer limiar máximo aceitável de fallback;
- permitir falha do pipeline se o nível de degradação ficar alto.

**Critério de conclusão**
O pipeline continua robusto sem virar uma caixa-preta silenciosa.

---

## Bloco 5 - Transparência, automação e documentação

### 12. Exportar diagnósticos do modelo para o painel

**Arquivos principais**
- `R/03_projecao.R`
- `R/06_exportar_painel.R`
- `painel/painel.qmd`

**Ações**
- exportar CSV próprio de diagnóstico;
- incluir modelo vencedor, métricas, ranking e status de fallback;
- expor a magnitude do ajuste de reconciliação quando fizer sentido.

**Critério de conclusão**
O painel deixa de operar como caixa-preta.

### 13. Separar rebuild analítico de deploy do painel

**Arquivos principais**
- `.github/workflows/publish-painel.yml`
- `.github/workflows/rebuild-dados.yml`

**Ações**
- criar workflow de rebuild analítico;
- deixar o workflow de deploy focado em renderização/publicação;
- condicionar a publicação a uma base analítica válida.

**Critério de conclusão**
Deploy visual e rebuild estatístico passam a ser processos distintos e governáveis.

### 14. Atualizar documentação técnica e operacional

**Arquivos principais**
- `README.md`
- `painel/metodologia.html`
- `docs/arquitetura.md`
- `docs/qa.md`
- `docs/modelagem.md`

**Ações**
- documentar nova arquitetura;
- explicar horizonte principal vs exploratório;
- registrar a família final de modelos;
- explicar QA, cache, logging e processo de publicação.

**Critério de conclusão**
Um terceiro consegue entender, rodar e manter o projeto sem depender de memória tácita.

---

## Itens deliberadamente deixados para uma fase futura

### Fase metodológica futura

- criação da camada `xreg`;
- base de indicadores externos por UF e ano;
- comparação formal com `MinT` ou `middle-out`;
- revisão estrutural das bandas de incerteza com bootstrap/simulação.

Esses itens devem começar somente depois que o baseline univariado estiver:

- reproduzível;
- auditável;
- com QA coercitivo;
- com seleção de modelos metodologicamente coerente.

---

## Sequência sugerida de commits

1. `Documenta: adiciona plano de reforma do projeto`
2. `Infraestrutura: adiciona renv e configuração central`
3. `Infraestrutura: adiciona seed global, logs e metadados de cache`
4. `Qualifica: torna checagens de consistência bloqueantes`
5. `Modela: redesenha validação cruzada para múltiplos horizontes`
6. `Modela: alinha seleção e projeção final`
7. `Simplifica: reduz família de modelos do baseline univariado`
8. `Expõe: exporta diagnósticos do modelo para o painel`
9. `Automatiza: separa rebuild analítico e deploy do painel`
10. `Documenta: atualiza readme e documentação técnica`

---

## Resumo executivo

O projeto já tem estrutura de produto institucional, mas a próxima rodada deve focar em fortalecer o que já existe, e não em expandir escopo.

Nesta reforma, a prioridade é:

1. estabilizar o pipeline atual;
2. tornar o resultado reprodutível e coercitivo;
3. corrigir o desenho de seleção dos modelos univariados;
4. só então ampliar transparência e automação.

`xreg` fica fora desta fase por falta de séries auxiliares adequadas no momento.
