# Persistência de votações

`Camara::Legislation::Voting` pertence a `Camara::Legislation` e usa a tabela
`camara_votings`. Cada registro representa uma decisão concluída. O ID interno
Rails é independente do `external_id` alfanumérico da Câmara, como `2355754-35`.
O índice único protege essa identidade inclusive em escritas concorrentes e em
operações em lote. Não se deduplicam votações diferentes por data ou descrição.

## Contrato de atributos

| Campo da fonte | Atributo local | Política |
| --- | --- | --- |
| `id` | `external_id` | String obrigatória, única; nunca converter para inteiro. |
| `data` | `occurred_on` | Data civil obrigatória, sem inventar hora de ocorrência. |
| `dataHoraRegistro` | `registered_at` | Instante do registro no sistema, opcional e independente de `data`. |
| `idOrgao` | `body_external_id` | Identificador externo em string, opcional. |
| `siglaOrgao` / `uriOrgao` | `body_acronym` / `body_source_uri` | Snapshot opcional da fonte. |
| `idEvento` / `uriEvento` | `event_external_id` / `event_source_uri` | Referência externa opcional, sem FK. |
| `descricao` | `description` | Texto original, sem extrair resultado por inferência. |
| `aprovacao` | `approved` | `1` → `true`, `0` → `false`, ausente/nulo → `nil`. |
| `uri` | `source_uri` | URI original obrigatória. |
| resumo completo | `raw_payload` | Objeto JSONB obrigatório, preservado pela importação da listagem. |
| detalhe completo | `detail_raw_payload` | Objeto JSONB opcional, preenchido pela hidratação. Preserva relações publicadas e campos desconhecidos do detalhe. |
| momento da coleta | `fetched_at` | Instante obrigatório gerado pela ingestão. |

O mapper `Camara::Legislation::Mappers::Voting.call(payload, fetched_at:)`
recebe um objeto retornado pela CongregaPlenum, de resumo ou de detalhe, e
produz os atributos locais. A ingestão fornece `fetched_at` como um `Time`; o
mapper preserva o payload original e converte o instante da coleta para UTC.
Valores de `aprovacao` fora do contrato geram `Mappers::ContractError`, com o
recurso e o campo. O model recebe os atributos normalizados.
`false` significa não aprovado, o que também pode incluir quórum insuficiente;
a trait `:rejected` prepara esse valor técnico e não comprova o motivo.

Órgão, evento, descrição e instante de registro podem permanecer desconhecidos.
Não há FK nem proposição única associada: objetos possíveis e proposições
afetadas continuam distintos no payload até a modelagem das relações.

## Hidratação

`Camara::Ingestion::HydrateVoting.call(external_id:)` busca o detalhe, os
votos e as orientações de uma votação já importada. Legislation aplica os
três recursos juntos depois de validar as respostas e mapear os registros.
A listagem pode atualizar o resumo sem apagar o payload detalhado ou os
identificadores de órgão e evento que omitiu.

Cada recurso guarda seu instante de coleta nas colunas `detail_hydrated_at`,
`votes_hydrated_at` e `orientations_hydrated_at`. O resultado informa as
contagens e esses instantes. Uma observação anterior às já persistidas é
descartada com status `superseded`. Se a fonte falhar, `FetchError` identifica
o recurso afetado e os já obtidos, com a exceção original como causa.

A migração adiciona quatro colunas anuláveis. Votações já importadas
continuam disponíveis e ganham os campos na primeira hidratação. Para
reverter o código sem perder os detalhes coletados, mantenha as colunas.

## Datas e fuso horário

`dataHoraRegistro` indica quando a tramitação foi registrada, não quando a
votação ocorreu. Não se exige que sua data seja igual a `occurred_on` e não se
preenche um campo ausente usando o outro.

Horários com offset explícito conservam o instante indicado. Para horários sem
offset, a política local é interpretá-los em `Brasilia` (`America/Sao_Paulo`),
conforme `config.time_zone`, usando as regras históricas de horário de verão
desse fuso. Isso é uma decisão do Tesa, não uma garantia de offset da fonte.
O mapper usa `Time.zone`, rejeita datas inválidas e reporta horários locais
ambíguos ou inexistentes como erros de contrato.
Instantes são persistidos em UTC; o texto original permanece no `raw_payload`.
`occurred_on` é `date` e não passa por conversão de fuso.

## Leitura e operação

`Camara::Ingestion::ImportVotingsPage.call(sync_run_id:, page:)` importa
uma página fora de qualquer transação aberta pelo chamador. A execução deve
estar em andamento e conter `start_date` e `end_date` no mesmo ano civil.
Use `items_per_page` nos filtros para manter um tamanho fixo durante a execução.
Quando ausente, vale o máximo configurado pela CongregaPlenum.

O resultado contém a quantidade recebida, a quantidade gravada, os IDs
externos e a próxima página possível quando a página estiver cheia. Uma
página vazia encerra a paginação. O checkpoint é registrado após o commit.
Reprocessar uma página aplica correções da fonte com o mesmo ID e mantém a
contagem acumulada. Exceções de HTTP, contrato ou persistência são propagadas
ao chamador, que controla a conclusão ou falha da execução.

### Paginação retomável

`Camara::Ingestion::PaginateVotings.call(sync_run_id:)` processa até uma
página por chamada e retorna `status`, `page`, `next_page` e o resultado da
importação quando houve consulta. O chamador usa `next_page` para decidir
quando prosseguir. O coordenador mantém o progresso no `SyncRun`, e
`Legislation` continua responsável pela persistência das votações.

- `continue` indica a próxima página após o último checkpoint.
- `complete` indica que uma página curta ou vazia foi confirmada. O instante
  `pagination_completed_at` é gravado com o checkpoint, depois do commit da
  página. A execução permanece disponível para as etapas seguintes.
- `page_limit_reached` indica que o limite foi atingido com a última página
  cheia. O limite é salvo em `filters["max_pages"]` e o padrão é 1.000 páginas.

Novas execuções começam com 100 itens por página e ordenação por `id`
crescente. O tamanho e a ordenação ficam nos filtros. Execuções com checkpoint
criado pela importação anterior preservam a ordem original por
`dataHoraRegistro` decrescente, quando ainda não há ordem registrada.

Sem datas, a API da Câmara usa uma janela móvel de 30 dias. No Tesa, use
`filters: { "mode" => "incremental" }` para registrar uma janela fixa na
primeira tentativa. Ela inclui o dia atual e até os 29 dias anteriores do
mesmo ano civil, no fuso da aplicação. Uma tentativa posterior usa as mesmas
datas. Para alcançar o ano anterior, crie outra execução com o intervalo
explícito.

O marcador de conclusão é opcional e a migração preserva checkpoints
existentes. Uma execução antiga sem marcador pode confirmar a página
seguinte ao retomar. Se for preciso voltar ao código anterior, mantenha a
coluna para preservar os marcadores registrados.

Os scopes locais `during(date_range)`, `for_body(external_id)` e
`with_known_result` são combináveis. O período inclui as extremidades de um
Range inclusivo. Resultado conhecido inclui tanto `true` como `false`.

Aplicar `20260907235500_create_camara_votings` com `bin/rails db:migrate` antes
dos futuros consumidores. A tabela começa vazia, sem backfill ou chamadas de
rede. Uma falha de migration é transacional no PostgreSQL; verificar
`bin/rails db:migrate:status` e executar novamente após corrigir a causa.
O rollback com `bin/rails db:migrate:down VERSION=20260907235500` remove a tabela:
interromper consumidores e exportar os dados antes, confirmando explicitamente
o descarte do histórico se o ambiente já tiver votações. O retorno ao código
anterior também pode manter a tabela, evitando perda de dados.

Monitorar erros de validação e `ActiveRecord::RecordNotUnique` nos futuros
importadores. Para atualizações da fonte, usar operação idempotente apoiada no
índice único; este model não implementa a orquestração de importação.

Fonte: [conceitos e limitações das votações nos Dados Abertos da Câmara](https://dadosabertos.camara.leg.br/howtouse/2020-02-07-dados-votacoes.html).
