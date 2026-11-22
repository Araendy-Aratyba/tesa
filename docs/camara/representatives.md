# Cadastros de representantes

`Camara::Ingestion` coordena a coleta e registra as execuções. A API pública de
`Camara::Representatives` entrega as respostas aos importadores do módulo.
Trate `external_id` como string canônica para identidade. Os cadastros e os
snapshots publicados nos votos são mantidos em seus respectivos módulos.

## Legislaturas

O cadastro armazena os limites oficiais inclusivos e preserva o payload da
última observação aceita. Na API da Câmara o `id` identifica o número da
legislatura. O ano eleitoral fica vazio quando a fonte omite o campo.
`Camara::Representatives::Legislature.covering(date)` pode retornar zero, uma
ou várias linhas. Os intervalos históricos podem ter durações diferentes.

Em desenvolvimento, execute `bin/rails db:prepare` e inicie o worker com
`bin/jobs start --mode=async`. No console Rails, use o mesmo Service para
agendar a lista ou o detalhe de um ID externo.

```ruby
start = Camara::Ingestion::StartRepresentativeSync
start.call(resource: :legislatures)
start.call(resource: :legislatures, external_id: 57)
```

O resultado informa `sync_run_id`, `status` e `error`. Consulte `page`,
`processed_count` e o status por `Camara::Ingestion::PublicApi.fetch`.
A lista segue a continuação publicada pela Câmara. Se um processo cair antes
de enfileirar a próxima página, confirme a ausência do job e reenvie
`Camara::Ingestion::SyncRepresentativeCatalogJob` com o ID da execução em
andamento e a página após o checkpoint. Use `page: nil` para um detalhe.
Uma execução com falha terminal pode ser iniciada de novo pelo Service.

A gem aplica suas retentativas HTTP configuradas dentro de cada tentativa do
job. O job permite até três tentativas para conexão, HTTP 429 e HTTP 5xx.
Uma falha terminal preserva as páginas confirmadas e é registrada na execução.

## Partidos

O ID oficial é a identidade do partido. A sigla representa o valor publicado
no catálogo e pode mudar ou se repetir entre IDs. A situação vem do detalhe,
e uma atualização da lista preserva a última situação e o payload de detalhe.
Uma ausência na lista conserva o cadastro existente. A coleta jamais
reatribui a filiação publicada nos votos.

```ruby
start = Camara::Ingestion::StartRepresentativeSync
start.call(resource: :parties)
start.call(resource: :parties, external_id: 36898)
```

Uma importação pela primeira vez via detalhe também preserva os campos de
identidade e nome. Uma execução da lista atualiza essas informações quando a
Câmara publica um valor posterior.

## Deputados

A lista exige o ID da legislatura consultada. Essa legislatura pode ainda
não ter sido importada. Cada linha da lista é uma observação, e o catálogo
conserva variantes do mesmo deputado na mesma legislatura. A identidade
permanece única. Para cada variante, `first_seen_at` e `last_seen_at` são
instantes de coleta. O total da execução conta linhas recebidas por página
confirmada, incluindo variantes e linhas idênticas devolvidas pela fonte.

```ruby
start = Camara::Ingestion::StartRepresentativeSync
start.call(resource: :deputies, legislature_id: 56)
start.call(resource: :deputies, external_id: 62881)
```

Hidrate separadamente IDs selecionados. O detalhe válido fornece os campos do
cadastro atual em `ultimoStatus`. A identidade e suas observações continuam
consultáveis quando o detalhe falta. `Deputy.with_electoral_name(name)`,
`from_state(uf)` e `with_situation(situation)` consultam o cadastro hidratado.
O payload bruto do detalhe é interno e pode incluir dados pessoais. As
observações sem vigência registrada não atribuem filiação a uma data e os
votos preservam a filiação publicada em cada snapshot.
