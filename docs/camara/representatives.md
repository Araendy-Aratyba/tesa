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
