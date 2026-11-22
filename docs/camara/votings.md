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

### Iniciar uma sincronização anual

Em desenvolvimento, prepare os bancos principal e de fila. Depois inicie
o worker em um terminal e enfileire o comando em outro.

```bash
bin/rails db:prepare
bin/jobs start --mode=async
```

```bash
bin/rails -T camara
bin/rails 'camara:sync_votings[2025]'
```

O modo `async` mantém os workers do Solid Queue no processo do supervisor
local e usa a fila persistida no PostgreSQL. No Docker Compose, use
`docker compose run --rm app` antes de cada comando. O comando anual retorna
após enfileirar a primeira página. O worker faz as chamadas à Câmara e agenda
as páginas e hidratações seguintes.

O ano deve ter quatro dígitos e estar entre 1935 e o ano corrente no fuso
da aplicação. A Câmara lista arquivos a partir de 1935 e há lacunas em
anos históricos. O intervalo vai de 1º de janeiro a 31 de dezembro do ano
informado. [Catálogo de arquivos da Câmara](https://dadosabertos.camara.leg.br/swagger/api.html?tab=staticfile)

O comando imprime `sync_run_id` e o status inicial `running`. No console,
consulte `Camara::Ingestion::PublicApi.fetch(sync_run_id: ID)` com o ID
impresso. `page`, `processed_count`, `failed_count` e
`pagination_completed_at` mostram o avanço. O marcador de paginação indica
que todas as páginas foram lidas. A execução continua `running` ao fim da
paginação e bloqueia outro disparo anual até atingir um estado terminal.
A hidratação tem sua própria fila.

Ano inválido, execução anual ativa para o mesmo intervalo ou rejeição da
fila retornam código de saída 1. Em caso de duplicidade, a mensagem exibe o
ID da execução existente. Se a fila rejeitar o envio, a execução recebe o
status `failed` e uma nova chamada pode criar outra. Se o processo cair
entre o commit do registro e o envio, confirme que o primeiro job está
ausente da fila antes de reenfileirar `Camara::Ingestion::SyncVotingsPageJob`
com `sync_run_id: ID` e `page: 1` para retomar a mesma execução.

### Coleta pelo Solid Queue

`Camara::Ingestion::SyncVotingsPageJob.perform_later(sync_run_id:, page:)`
trabalha na fila `camara_sync`. A execução deve estar em andamento. Se o
chamador passar `start_date` e `end_date`, ambas devem ser strings ISO
iguais às datas da execução. O primeiro job do modo incremental pode
omiti-las. As páginas seguintes carregam as datas já fixadas.

O Solid Queue usa uma vaga por execução, com expiração de 15 minutos para
recuperação se um worker cair. Depois do commit da página, o checkpoint guarda
os IDs pendentes de envio. O job enfileira uma hidratação por ID em
`camara_hydration`, enfileira a próxima página quando indicada e confirma o
envio. Reexecutar uma página já enviada é inócuo. Uma interrupção durante o
envio pode repetir jobs já aceitos pela fila. A hidratação e o checkpoint
são idempotentes.

A CongregaPlenum mantém as próprias retentativas por requisição. O job
permite até três tentativas para falhas de conexão, limite de taxa ou HTTP
5xx. Falhas permanentes e esgotamento de tentativas são registrados no
`SyncRun`. Uma página final válida encerra a paginação e deixa a execução
disponível para as outras etapas. Se o limite for atingido com uma página
cheia, o job envia as hidratações confirmadas e registra a falha do limite.

A migração de `pending_voting_ids` é anulável. Para reverter o código,
mantenha a coluna enquanto houver páginas pendentes de envio.

### Hidratação pelo Solid Queue

`Camara::Legislation::HydrateVotingJob.perform_later(external_id:, sync_run_id:)`
recebe o identificador externo da votação como string e o ID da execução.
O job chama a API pública de Ingestion para buscar os três recursos. O Service
de Legislation valida e persiste os dados em uma transação por votação.
O Solid Queue reserva uma vaga por votação, mesmo quando os jobs vêm de
execuções diferentes, com expiração de 15 minutos para recuperar a vaga se
um worker cair. A transação de Legislation também usa bloqueio por votação
e índices únicos para proteger a gravação concorrente.

Conexão, HTTP 429 e HTTP 5xx permitem até três tentativas do job, incluindo
a primeira. As demais esperam um intervalo crescente com jitter. A gem faz
até `CAMARA_API_RETRIES` retentativas por requisição dentro de cada tentativa
do job. Com o padrão de três retentativas da gem, são até 12 chamadas por
endpoint ao longo de uma execução do job com suas retentativas. Erros HTTP
permanentes e payload inválido encerram o job na primeira ocorrência.

Uma falha terminal fica visível nos jobs falhos do Solid Queue. A auditoria
em `camara_voting_hydration_failures` guarda o ID do job, a classe da falha e
o número de tentativas do job. `SyncRun.failed_count` aumenta uma vez por
votação com falha terminal naquela execução. Um novo erro terminal para a
mesma votação atualiza o registro existente. A auditoria é histórica e o
job de páginas pode continuar importando os demais resumos. O resumo e a
última hidratação confirmada permanecem disponíveis para consulta.

Aplique a migração `20261122080000` antes de iniciar os workers com o novo
código. Jobs legados continuam executáveis e carregam apenas o ID da votação.
Para voltar ao código anterior, processe primeiro os jobs novos da fila,
incluindo os agendados para retentativa, e preserve a tabela de auditoria.

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

### Piloto com a API oficial

Use uma instância descartável de PostgreSQL e execute o piloto manualmente.
O script exige `CAMARA_LIVE_PILOT=1`, ambiente de desenvolvimento e tabelas
de execuções e votações vazias. Escolha um dia civil já encerrado.

```bash
docker run --rm -d --name tesa-camara-pilot \
  -e POSTGRES_PASSWORD=postgres -p 127.0.0.1:55418:5432 postgres:16.15-alpine
docker exec tesa-camara-pilot pg_isready -U postgres -h 127.0.0.1
(
  unset DATABASE_URL QUEUE_DATABASE_URL
  export RAILS_ENV=development DB_HOST=127.0.0.1 DB_PORT=55418
  export DB_USERNAME=postgres DB_PASSWORD=postgres
  bin/rails db:prepare && \
    CAMARA_LIVE_PILOT=1 bin/rails runner script/camara/voting_pilot.rb 2020-03-25
)
```

Se o PostgreSQL ainda estiver iniciando, repita o `pg_isready` até aceitar
conexões. O piloto executa os jobs reais usando uma fila em memória própria
do processo. Ele consulta uma única página e hidrata até oito votações.
Cada hidratação consulta detalhe, votos e orientações. O limite é de 25
chamadas ao cliente e a gem usa timeout de conexão e leitura de 10 segundos.
O piloto interrompe ao detectar retentativa agendada, e as retentativas
internas da gem ficam desativadas apenas nesse processo.

A saída JSON informa o ID do `SyncRun`, duração, checkpoint, IDs externos e
contagens de filhos. O piloto encerra o `SyncRun` como `succeeded` após
conferir a persistência de todos os jobs. Em caso de erro, o ID da execução
fica disponível para examinar a auditoria no banco isolado.

Depois de conferir a saída, remova o banco descartável encerrando o
contêiner criado acima. O `--rm` remove o contêiner e seu volume anônimo.

```bash
docker stop tesa-camara-pilot
```
