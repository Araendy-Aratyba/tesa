<!-- Resuma o trabalho no título do pull request. Prefira um título curto e objetivo. -->

## Motivação

<!--
Descreva o problema, a necessidade ou a oportunidade que motivou este pull
request. Explique por que a mudança é necessária agora e qual resultado se
espera obter.

Inclua imagens, vídeos, diagramas, payloads reduzidos ou fluxos quando ajudarem
a esclarecer o contexto. Não inclua credenciais, dados pessoais ou informações
sensíveis.
-->

## Regras de negócio e termos

<!--
Descreva as regras de negócio, conceitos e termos necessários para compreender
a mudança. Para dados legislativos, diferencie fatos confirmados, informações
desconhecidas e hipóteses; registre também limitações da fonte.

Quando aplicável, inclua referências oficiais da Câmara dos Deputados e explique
conceitos como votação, evento, proposição, orientação de bancada, legislatura,
CEAP, PPA, LDO ou LOA.

Se não houver regra de negócio relevante, escreva "Não se aplica".
-->

## Descrição técnica da solução

<!--
Descreva as alterações e decisões técnicas com detalhes suficientes para uma
revisão futura. Informe, quando aplicável:

- componentes, modelos, serviços, tarefas assíncronas e endpoints afetados;
- mudanças de esquema, índices, restrições e estratégia de migração;
- contratos externos, paginação, idempotência, retentativas e limites de concorrência;
- decisões consideradas e respectivas contrapartidas;
- compatibilidade, observabilidade e comportamento em caso de falha.

Inclua diagramas, exemplos de entrada/saída ou screenshots quando tornarem a
solução mais clara.
-->

## Tipo de mudança

<!-- Marque com `x` todas as opções aplicáveis. -->

- [ ] Nova funcionalidade — adiciona comportamento sem quebrar o existente.
- [ ] Correção de bug — corrige comportamento sem introduzir incompatibilidade.
- [ ] Mudança incompatível — altera ou remove comportamento já disponível.
- [ ] Manutenção ou refatoração — melhora segurança, desempenho ou estrutura interna.
- [ ] Documentação.
- [ ] Dependências, CI ou infraestrutura.
- [ ] Migração de banco de dados — altera esquema, índices ou dados persistidos.
- [ ] Job, tarefa recorrente, importação ou carga histórica de dados.

## Como foi testado?

<!--
Descreva os cenários exercitados, os comandos executados e os resultados. Informe
o ambiente utilizado e eventuais partes não testadas. Testes automatizados não
devem depender da disponibilidade de serviços externos.

Exemplo:

```bash
bin/rspec spec/services/camara/...
bin/ci
```
-->

- [ ] RSpec focado.
- [ ] Suíte completa com `bin/rspec`.
- [ ] Verificações completas com `bin/ci`.
- [ ] Ambiente de desenvolvimento local.
- [ ] Docker Compose/Dev Container.
- [ ] Teste rápido controlado com serviço externo.
- [ ] Validação manual de interface.
- [ ] Não se aplica — mudança exclusivamente documental.

## Mudanças de ambiente e operação

<!--
Informe variáveis de ambiente, credenciais, serviços, filas, agendamentos, volumes,
migrações, comandos de implantação ou cargas históricas necessárias. Inclua valores padrão
seguros e a ordem de aplicação.

Se não houver mudança, escreva "Nenhuma".
-->

## Análise de risco e rollback

<!--
Descreva o impacto potencial, os principais modos de falha, como observar a
mudança depois do deploy e como reverter com segurança.

Para migrações, jobs ou importações, explique também idempotência, retomada,
compatibilidade durante a implantação e recuperação dos dados. Não proponha limpeza
ou rollback destrutivo sem alvo e procedimento explícitos.
-->

## Interface

<!--
Para mudanças visuais, inclua screenshots ou vídeos dos principais estados,
inclusive vazio, carregando, erro e sucesso quando aplicável. Descreva as
validações de acessibilidade e aprimoramento progressivo.

Remova esta seção quando não houver mudança de interface.
-->

## Checklist

- [ ] Mantive o pull request focado e sem alterações não relacionadas.
- [ ] Relacionei a issue correspondente e documentei dependências relevantes.
- [ ] Adicionei ou atualizei testes para mudanças de comportamento.
- [ ] Atualizei documentação, exemplos e guias operacionais quando necessário.
- [ ] Executei `bin/ci` ou registrei acima as verificações não executadas e o motivo.
- [ ] Os checks `scan_ruby`, `scan_js`, `lint` e `test` do GitHub Actions passaram.
- [ ] Migrações e alterações de dados possuem estratégia segura de aplicação e reversão.
- [ ] Jobs, importações e cargas históricas são idempotentes e retomáveis quando aplicável.
- [ ] Preservei o significado e as limitações dos dados publicados pela Câmara.
- [ ] Não incluí credenciais, dados pessoais, payloads sensíveis ou segredos em logs.
- [ ] Considerei segurança, acessibilidade e aprimoramento progressivo quando aplicável.
- [ ] Solicitei a revisão dos responsáveis definidos no `CODEOWNERS`.

## Links

<!--
Use palavras-chave do GitHub para relacionar ou fechar issues após o merge:

Closes #123
Relates to #456

Inclua também PRs/issues da CongregaPlenum, documentação técnica, referências da
Câmara, decisões arquiteturais e follow-ups relevantes.
-->
