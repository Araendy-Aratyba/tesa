# Votos individuais e orientações de bancada

`Camara::Legislation::Vote` e `Camara::Legislation::Orientation` pertencem a
`Camara::Legislation` e são filhos independentes de
`Camara::Legislation::Voting`. Um voto registra o posicionamento publicado de um
parlamentar; uma orientação registra a recomendação de uma liderança. Nenhum
deles representa presença ou ausência parlamentar.

Os mappers `Camara::Legislation::Mappers::Vote` e
`Camara::Legislation::Mappers::Orientation` recebem um objeto de cada vez em
`.call(payload, fetched_at:)`. Aceitam os campos da API e os equivalentes do
arquivo anual descritos abaixo. O vínculo local `voting_id` é atribuído pela
ingestão. O resultado inclui o payload original e o horário de coleta em UTC.

Na hidratação, somente os registros ausentes de uma coleção completa e
validada são removidos. Uma lista explícita vazia indica que a fonte retornou
zero registros publicados. A CongregaPlenum 0.2 também converte respostas
sem `dados` ou com `dados: null` em listas vazias. O adaptador de hidratação
valida a resposta antes dessa conversão e rejeita coleções com indicador de
próxima página. Nesses casos, a versão já persistida é preservada.

## Votos individuais

Cada registro em `camara_votes` é identificado por
`(voting_id, deputy_external_id)`. A identidade é protegida por índice único no
PostgreSQL para permitir reimportação idempotente: uma nova observação do mesmo
parlamentar na mesma votação deve atualizar o registro existente.

| Campo da fonte | Atributo local | Política |
| --- | --- | --- |
| `deputado_.id` / `deputado_id` | `deputy_external_id` | String obrigatória; não depende da existência futura de um model de deputado. |
| `tipoVoto` / `voto` | `position` | Texto aberto e anulável; não usar enum nem inferir ausência. |
| `dataRegistroVoto` / `dataHoraVoto` | `recorded_at` | Instante opcional em UTC depois do mapeamento. |
| `deputado_.uri` / `deputado_uri` | `deputy_source_uri` | URI publicada no momento do voto. |
| `deputado_.nome` / `deputado_nome` | `deputy_name` | Nome parlamentar publicado no momento do voto. |
| partido, UF e legislatura | `party_*`, `state_acronym`, `legislature_external_id` | Snapshot histórico; não é substituído pelo cadastro atual. |
| foto e e-mail | `deputy_photo_url`, `deputy_email` | Snapshot opcional da fonte. |
| objeto completo | `raw_payload` | Objeto JSONB obrigatório, preservado integralmente. |
| momento da coleta | `fetched_at` | Instante obrigatório da observação. |

No conjunto anual de 2026 foram observados `Sim`, `Não`, `Abstenção`,
`Obstrução`, `Artigo 17` e valor vazio. A lista é descritiva, não fechada:
valores novos permanecem em `position` e em `raw_payload`. Valor vazio ou nulo
significa apenas posição desconhecida no registro recebido; não vira ausência,
abstenção ou qualquer outro valor sintético.

## Orientações de bancada

Cada registro em `camara_orientations` é identificado por
`(voting_id, group_key)`. A `group_key` é uma identidade técnica estável que o
mapper deve derivar assim:

1. quando existir `uriPartidoBloco`/`uriBancada`, usar `uri:<URI completa>`;
2. sem URI na API, usar
   `leadership:<codTipoLideranca>:<siglaPartidoBloco normalizada>`;
3. em arquivo anual sem URI e sem código de liderança, usar
   `bancada:<siglaBancada normalizada>`.

O mapper normaliza a sigla para a chave removendo os espaços nas extremidades,
usando maiúsculas e normalização Unicode canônica. A sigla original permanece
no snapshot. Sem URI, a sigla anual por si só não estabelece equivalência com
uma bancada da API. `leadership_type`, `group_acronym`, `group_external_id`
(de `codPartidoBloco`) e `group_source_uri` preservam separadamente os campos
publicados.

`position` também é texto aberto e anulável. No conjunto anual de 2026 foram
observados `Sim`, `Não`, `Liberado`, `Obstrução` e valor vazio. Vazio não é
sinônimo de `Liberado`, e valores novos não são rejeitados por enum.

## Integridade, reimportação e exclusão

Os dois models validam a identidade no Rails, enquanto os índices compostos
garantem a unicidade sob concorrência e em operações em lote. Importadores devem
usar `upsert_all` (ou operação equivalente) com
`index_camara_votes_identity` ou `index_camara_orientations_identity`, sempre
atualizando `raw_payload` e `fetched_at` depois de uma observação confirmada.

As FKs pertencem integralmente ao módulo `Legislation`. Elas bloqueiam a remoção
direta de uma votação que ainda possua filhos. Uma exclusão explicitamente
autorizada por `voting.destroy!` remove votos e orientações com
`dependent: :delete_all`; a aplicação não deve usar esse caminho como forma de
reconciliar coleção vazia ou falha parcial.

Uma votação recém-importada começa com coleções vazias. Isso significa somente
que nenhum voto ou orientação foi persistido. Em votações simbólicas, votos
individuais podem não existir; não devem ser criados registros sintéticos de
ausência.

Fonte: [arquivos anuais de votos e orientações](https://dadosabertos.camara.leg.br/swagger/api.html?tab=staticfile)
e [limitações conhecidas das votações](https://dadosabertos.camara.leg.br/howtouse/2020-02-07-dados-votacoes.html).
