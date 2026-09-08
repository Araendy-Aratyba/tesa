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
| objeto completo | `raw_payload` | Objeto JSONB obrigatório, não vazio; preserva campos desconhecidos e relações. |
| momento da coleta | `fetched_at` | Instante obrigatório gerado pela ingestão. |

O mapeamento de payload e a integração HTTP serão implementados em trabalho
posterior. O model recebe atributos normalizados e não conhece a CongregaPlenum.
O mapper deverá rejeitar valores inesperados de `aprovacao` antes da atribuição:
o cast booleano genérico do Rails não valida o contrato externo.
`false` significa não aprovado, o que também pode incluir quórum insuficiente;
a trait `:rejected` prepara esse valor técnico e não comprova o motivo.

Órgão, evento, descrição e instante de registro podem permanecer desconhecidos.
Não há FK nem proposição única associada: objetos possíveis e proposições
afetadas continuam distintos no payload até a modelagem das relações.

## Datas e fuso horário

`dataHoraRegistro` indica quando a tramitação foi registrada, não quando a
votação ocorreu. Não se exige que sua data seja igual a `occurred_on` e não se
preenche um campo ausente usando o outro.

Horários com offset explícito conservam o instante indicado. Para horários sem
offset, a política local é interpretá-los em `Brasilia` (`America/Sao_Paulo`),
conforme `config.time_zone`, usando as regras históricas de horário de verão
desse fuso. Isso é uma decisão do Tesa, não uma garantia de offset da fonte.
Na ingestão futura, o mapper deve usar esse fuso explicitamente, rejeitar datas
inválidas e tratar horários locais ambíguos/inexistentes como erro de contrato.
Instantes são persistidos em UTC; o texto original permanece no `raw_payload`.
`occurred_on` é `date` e não passa por conversão de fuso.

## Leitura e operação

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
