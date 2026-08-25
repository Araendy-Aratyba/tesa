# Instruções de arquitetura e implementação para agentes de IA

Este arquivo se aplica a todo o repositório Tesa. Agentes de IA devem lê-lo
antes de planejar ou alterar código. Instruções mais específicas em um
`AGENTS.md` descendente podem complementar estas regras para aquele diretório,
mas não podem enfraquecer fronteiras, segurança ou semântica de dados definidas
aqui.

## Objetivo do projeto

O Tesa é uma aplicação Rails para coletar, persistir, relacionar e apresentar
dados legislativos da Câmara dos Deputados. A integração HTTP é feita por meio
da gem `congrega_plenum`; o Tesa controla casos de uso, persistência,
idempotência, jobs, consultas, apresentação e observabilidade.

O sistema deve ser implementado como um **monólito modular**, usando
**Services**, **Query Objects** e **Presenters** de forma intencional.

Esses padrões ocupam níveis diferentes:

- o monólito modular define propriedade, fronteiras e dependências;
- Services executam comandos e casos de uso;
- Query Objects implementam leituras não triviais;
- Presenters adaptam resultados já carregados para views.

Não transforme os padrões em cerimônia. Uma consulta simples, uma validação do
model ou uma renderização direta não precisa ganhar uma classe nova.

## Regras obrigatórias de trabalho

1. Preserve mudanças não relacionadas que já estejam no checkout.
2. Mantenha cada alteração limitada à issue ou objetivo em execução.
3. Antes de implementar, identifique o módulo proprietário e o fluxo como
   leitura ou escrita.
4. Não faça chamadas reais à Câmara na suíte padrão.
5. Não altere silenciosamente o significado dos dados da fonte.
6. Não misture orçamento legislativo, CEAP e execução orçamentária.
7. Não introduza Rails Engines, microsserviços ou Packwerk sem uma decisão
   arquitetural aprovada em issue própria.
8. Não altere a gem `congrega_plenum` neste repositório. Quando uma issue exigir
   novo contrato da gem, implemente e publique no repositório da gem, valide a
   versão instalada e só então atualize o Tesa.
9. Novos comportamentos precisam de testes proporcionais ao risco.
10. Use os comandos e versões fixados no repositório; antes de entregar, execute
    as verificações focadas e, quando viável, `bin/ci`.

## Arquitetura modular

### Módulos proprietários

Use estes módulos como fronteiras de negócio:

| Módulo | Propriedade |
| --- | --- |
| `Camara::Ingestion` | execuções, checkpoints, backfills, agendamentos, falhas, frescor e observabilidade da coleta |
| `Camara::Legislation` | votações, votos, orientações, proposições e relações votação-proposição |
| `Camara::Representatives` | deputados, partidos, legislaturas, mandatos e vínculos temporais |
| `Camara::LegislativeBudget` | classificação e leitura orçamentária de proposições, como PPA, LDO, LOA e créditos |
| `Camara::Ceap` | despesas da Cota para o Exercício da Atividade Parlamentar |
| `Camara::Reporting` | projeções somente leitura que combinam mais de um módulo para telas e relatórios |

`Camara::Legislation::Proposition` é a entidade legislativa genérica.
`Camara::LegislativeBudget` classifica e consulta essas proposições; não mantém
uma segunda cópia da mesma entidade.

Execução orçamentária e financeira não pertence a `LegislativeBudget` nem a
`Ceap`. Ela requer fonte, contrato e módulo próprios em trabalho futuro.

### Direção permitida das dependências

```text
CongregaPlenum
      |
      v
Camara::Ingestion
      |
      +-----------> Camara::Legislation
      +-----------> Camara::Representatives
      +-----------> Camara::Ceap

Camara::LegislativeBudget ---> Camara::Legislation::PublicApi
Camara::Ceap ---------------> Camara::Representatives::PublicApi
Camara::Reporting ----------> APIs/projeções públicas de qualquer módulo
```

Regras:

- Não crie dependências cíclicas.
- Um módulo não consulta models, tabelas, scopes ou services internos de outro.
- Comunicação entre módulos ocorre por uma `PublicApi` e retorna valores,
  resultados ou projeções imutáveis.
- `Camara::Reporting` pode compor leituras de vários módulos. Qualquer join
  direto entre tabelas de módulos diferentes deve ficar isolado em um Query
  Object de reporting, ser somente leitura e ter a dependência documentada.
- Jobs, controllers e views não são atalhos para atravessar fronteiras.
- Foreign keys internas ao módulo são normais. Referências entre módulos devem
  preferir identificadores externos e snapshots; uma FK cruzada exige
  justificativa explícita na issue e no PR.

Exemplo de acesso entre módulos:

```ruby
snapshot = Camara::Representatives::PublicApi.find_snapshot(
  deputy_external_id: vote.deputy_external_id,
  at: voting.occurred_at
)
```

Não faça:

```ruby
Camara::Representatives::Deputy
  .joins(:mandates, :party)
  .find_by!(external_id: vote.deputy_external_id)
```

### Estrutura de arquivos

Use diretórios Rails convencionais e repita a fronteira no namespace:

```text
app/
├── models/camara/<module>/
├── services/camara/<module>/
├── queries/camara/<module>/
├── presenters/camara/<module>/
└── jobs/camara/<module>/
```

Exemplos:

```text
app/models/camara/legislation/voting.rb
app/services/camara/representatives/public_api.rb
app/services/camara/legislation/import_votings_page.rb
app/queries/camara/legislation/voting_search.rb
app/presenters/camara/legislation/voting_details.rb
app/jobs/camara/legislation/sync_votings_page_job.rb
```

Constantes correspondentes:

```ruby
Camara::Legislation::Voting
Camara::Representatives::PublicApi
Camara::Legislation::ImportVotingsPage
Camara::Legislation::Queries::VotingSearch
Camara::Legislation::Presenters::VotingDetails
Camara::Legislation::SyncVotingsPageJob
```

Não use um namespace adicional `Services`: o nome verbal do caso de uso já
comunica sua função. Use `Queries` e `Presenters` para tornar explícito que essas
classes são somente leitura ou apresentação.

Mantenha nomes de tabelas estáveis e legíveis, como `camara_votings` e
`camara_sync_runs`. Se a inferência do namespace produzir outro nome, declare
`self.table_name` explicitamente; não renomeie uma tabela apenas para refletir a
árvore de constantes.

Uma `PublicApi` expõe somente operações necessárias a outros módulos, delega a
Services ou Query Objects do módulo proprietário e não contém regra duplicada.
Para leitura, ela retorna uma projeção imutável em vez do Active Record interno:

```ruby
module Camara::Representatives::PublicApi
  DeputySnapshot = Data.define(
    :external_id,
    :electoral_name,
    :party_acronym,
    :state_acronym
  )

  def self.find_snapshot(deputy_external_id:, at:)
    Queries::DeputySnapshot.call(deputy_external_id:, at:)
  end
end
```

Todo arquivo novo deve carregar corretamente com Zeitwerk em eager load. Não
adicione `require` manual para contornar constante em caminho incorreto.

## Fluxos obrigatórios

### Escrita

```text
Controller ou Job
       |
       v
Service do módulo proprietário
       |
       +--> integração externa
       +--> mapper
       +--> models/transação
       +--> evento/checkpoint
       '--> Result imutável
```

### Leitura para view

```text
Controller
    |
    v
Query Object
    |
    v
registros pré-carregados ou projeção imutável
    |
    v
Presenter
    |
    v
View
```

### Execução assíncrona

```text
Scheduler ou Service de entrada
    |
    v
Job fino
    |
    v
Service idempotente
```

## Models

Models representam estado persistido e protegem invariantes locais.

Devem conter:

- associações pertencentes ao próprio módulo;
- validações de formato, presença e consistência local;
- métodos que expressem estado da entidade;
- scopes pequenos, reutilizáveis e pertencentes a uma tabela;
- enums somente quando o conjunto de valores é controlado pelo Tesa.

Não devem conter:

- orquestração de importação;
- chamadas HTTP;
- jobs enfileirados por callbacks opacos;
- consultas de dashboard;
- formatação para interface;
- acesso direto aos models internos de outro módulo.

Validação de unicidade no model não substitui índice único no banco. Dados de
fonte externa devem ter índice por identidade externa e operações idempotentes.

## Services

Um Service representa um comando ou caso de uso e possui nome verbal:

```ruby
Camara::Legislation::ImportVotingsPage
Camara::Legislation::HydrateVoting
Camara::Ingestion::StartAnnualVotingSync
Camara::Ceap::ImportExpenses
```

Use um Service quando a operação:

- coordena mais de um model ou componente;
- realiza escrita;
- chama integração externa;
- define fronteira transacional;
- emite evento ou enfileira trabalho;
- precisa ser invocada por controller, job, console e teste.

Não crie um Service que apenas delega um `find`, um scope ou uma formatação.

### Interface

Prefira uma entrada pública consistente:

```ruby
class Camara::Legislation::ImportVotingsPage
  Result = Data.define(:processed_count, :voting_ids, :next_page, :errors) do
    def success? = errors.empty?
  end

  def self.call(...)
    new(...).call
  end

  def initialize(sync_run:, page:, client: CongregaPlenum::VotingsService)
    @sync_run = sync_run
    @page = page
    @client = client
  end

  def call
    # caso de uso
  end
end
```

Regras:

- Use keyword arguments para entradas relevantes.
- Injete a fronteira externa quando isso tornar o teste e o contrato claros.
- Retorne um `Result` imutável e previsível quando houver progresso, próximo
  passo ou erros recuperáveis.
- Lance exceções específicas para falhas que impedem o caso de uso; não retorne
  `nil` para esconder falha.
- Não retorne `true`, `nil`, model ou hash de maneira variável conforme o fluxo.
- Não crie uma classe base de Service antes de haver comportamento realmente
  compartilhado.

### Transações e HTTP

Nunca mantenha uma transação aberta durante uma chamada HTTP:

```text
1. faça a chamada externa;
2. valide e mapeie o payload;
3. abra uma transação curta;
4. persista uma unidade idempotente;
5. confirme a transação;
6. atualize o checkpoint;
7. enfileire o próximo trabalho depois do commit.
```

## Query Objects

Query Objects implementam consultas não triviais e são estritamente somente
leitura.

Use um Query Object quando houver:

- vários filtros opcionais;
- joins ou preloads importantes;
- agregações;
- paginação e ordenação complexas;
- reutilização da mesma consulta;
- uma projeção para dashboard/relatório;
- composição autorizada entre módulos.

Exemplo:

```ruby
class Camara::Legislation::Queries::VotingSearch
  def self.call(...)
    new(...).call
  end

  def call
    scope = Camara::Legislation::Voting.all
    scope = scope.where(occurred_on: date_range) if date_range
    scope = scope.where(body_external_id:) if body_external_id
    scope.order(occurred_on: :desc, external_id: :desc)
  end
end
```

Regras:

- Não faça `create`, `update`, `delete`, `touch`, enqueue ou HTTP.
- Evite callbacks e efeitos colaterais.
- Dentro do módulo, pode retornar `ActiveRecord::Relation` para permitir
  paginação posterior.
- Ao atravessar módulos ou agregar dados, retorne projeções imutáveis, por
  exemplo `Data.define`.
- Precarregue associações necessárias para que Presenters não provoquem N+1.
- Um `find` simples e um scope local não precisam de Query Object.
- Consultas cross-module pertencem a `Camara::Reporting::Queries`, salvo quando
  uma dependência pública específica estiver definida no módulo consumidor.

## Presenters

Presenters transformam dados já carregados em valores próprios para uma view.

Use um Presenter quando houver:

- formatação de datas, números ou moeda;
- tradução de rótulos;
- estado vazio/desconhecido;
- classes visuais derivadas de estado;
- links ou texto alternativo;
- composição de campos para cards e tabelas.

Exemplo:

```ruby
class Camara::Legislation::Presenters::VotingDetails
  def initialize(voting, view_context:)
    @voting = voting
    @view_context = view_context
  end

  def result_label
    key = case voting.approved
          when true then "approved"
          when false then "rejected"
          else "unknown"
          end

    I18n.t("camara.votings.results.#{key}")
  end

  def occurred_on
    view_context.l(voting.occurred_on, format: :long)
  end

  private

  attr_reader :voting, :view_context
end
```

Regras:

- Não consulte banco, não faça HTTP e não chame Services.
- Não decida regras de negócio; apenas representa uma decisão já feita pelo
  domínio.
- Não corrija ou complete dados ausentes por suposição.
- Receba `view_context` explicitamente quando precisar de helpers.
- Use I18n para texto exibido ao usuário.
- Não devolva HTML `safe` construído com dados externos sem sanitização.
- Uma view que apenas imprime um atributo não precisa de Presenter.

## Controllers

Controllers devem:

- autenticar e autorizar;
- validar/permitir parâmetros;
- escolher um Service para comandos ou Query Object para leitura;
- construir Presenter para views quando necessário;
- decidir resposta HTTP, redirect e status.

Controllers não devem:

- conter transações;
- acessar a CongregaPlenum diretamente;
- montar joins complexos;
- implementar regras legislativas;
- formatar payload para a view;
- coordenar múltiplos models diretamente.

## Jobs e Solid Queue

Jobs são adaptadores assíncronos finos. Devem controlar fila, serialização,
concorrência, retentativas e falha terminal, delegando o caso de uso a um
Service.

Regras:

- Passe IDs e valores primitivos, não coleções nem payloads grandes.
- O Service chamado deve ser idempotente.
- Use `retry_on` somente para erros transitórios conhecidos.
- Erros `4xx` permanentes e payload inválido não entram em loop de retry.
- Documente a composição entre retry da gem e retry do job.
- Enfileire dependências após commit quando elas exigirem dados recém-gravados.
- Limite concorrência por execução ou identidade externa quando necessário.
- Jobs não chamam Presenters.

## Mappers e integração externa

A gem `congrega_plenum` é a fronteira HTTP oficial. O Tesa não deve duplicar
paginação, retry ou strings de endpoint que já pertençam à API pública da gem.

Mappers:

- pertencem ao módulo que controla o dado, por exemplo
  `Camara::Legislation::Mappers::Voting`;
- são objetos puros, sem banco e sem rede;
- convertem payload externo em atributos locais;
- preservam `raw_payload`;
- validam apenas campos indispensáveis;
- levantam erro de contrato com recurso/campo, sem registrar o payload completo.

Quando a gem não possuir um endpoint de alto nível necessário, a issue deve
decidir explicitamente entre estender a gem e usar temporariamente o Client de
baixo nível. Prefira estender e publicar a gem para contratos reutilizáveis.

## Regras semânticas dos dados da Câmara

Estas regras são obrigatórias em implementação, testes e apresentação:

- ID de votação é string e pode ser alfanumérico, como `2355754-35`.
- `approved` é triestado: `true`, `false` ou desconhecido (`nil`).
- Lista vazia de votos não significa que todos os deputados estavam ausentes.
- Votações simbólicas podem não possuir votos individuais.
- Uma votação é uma decisão concluída, não um evento ou sessão.
- Uma proposição pode ser afetada por várias votações.
- “Objeto possível” e “proposição afetada” são relações diferentes.
- Não escolha o primeiro objeto possível como objeto verdadeiro.
- Intervalos de votação não atravessam o ano civil; backfills são particionados
  por ano.
- Cadastro atual de deputado/partido não reescreve o contexto histórico de um
  voto ou despesa.
- CEAP é despesa do exercício do mandato, não execução da LOA e não despesa do
  partido atual.
- PPA, LDO e LOA pertencem ao processo legislativo; execução financeira começa
  depois da aprovação e depende de outras fontes.

Preserve campos normalizados para consulta e `raw_payload: jsonb` para
proveniência. Não transforme resposta inválida ou falha parcial em coleção
vazia.

## Banco de dados e idempotência

- Use PostgreSQL e migrations Rails.
- Identidades externas exigem índice único no banco.
- Valores monetários usam `decimal` com precisão/escala explícitas, nunca
  `float`.
- Instantes são persistidos em UTC e interpretados no fuso configurado da
  aplicação.
- HTTP acontece fora de transações.
- Use `upsert_all` ou operação equivalente apoiada por índice único quando a
  fonte puder corrigir registros.
- Checkpoint só avança depois do commit da unidade correspondente.
- Falha parcial não apaga dados confirmados nem aparece como sucesso.
- Migrations e backfills devem ter estratégia de aplicação, retomada e rollback.

## Testes por componente

### Models

- validações e invariantes;
- associações e FKs;
- índices únicos verificados por comportamento concorrente quando relevante;
- scopes locais.

### Services

- caminho de sucesso, falha e reexecução;
- fronteira transacional;
- idempotência;
- Result retornado;
- integração externa substituída por double verificável;
- falha externa não convertida em sucesso vazio.

### Query Objects

- filtros isolados e combinados;
- ordenação determinística;
- paginação/agregações;
- ausência de escrita;
- quantidade de queries/N+1 quando relevante.

### Presenters

- não acessar banco;
- formatação e I18n;
- estados `true`, `false`, `nil` e vazio;
- caracteres e textos vindos da fonte tratados com segurança.

### Jobs

- fila, argumentos e enqueue;
- delegação ao Service;
- retry apenas para erro transitório;
- falha terminal;
- controle de concorrência e próxima unidade.

### Requests e sistema

- autorização;
- wiring de Query Object/Service;
- respostas e redirects;
- estados visuais e acessibilidade;
- sem chamadas externas reais.

Use factories e fixtures contratuais pequenas. Smoke tests reais contra a Câmara
são opt-in, controlados e não pertencem ao CI padrão.

## Critério para escolher o padrão

Antes de criar uma classe, responda:

1. Qual módulo controla este comportamento?
2. É escrita/comando ou leitura?
3. Há regra ou orquestração suficiente para um Service?
4. A consulta é complexa/reutilizável o suficiente para um Query Object?
5. Existe adaptação real para view que justifique um Presenter?
6. O componente atravessa módulos? Se sim, está usando `PublicApi` ou Reporting?

Tabela de decisão:

| Necessidade | Componente |
| --- | --- |
| estado e invariantes locais | Model |
| comando, escrita ou integração | Service |
| leitura complexa/reutilizável | Query Object |
| adaptação para interface | Presenter |
| execução assíncrona | Job fino chamando Service |
| tradução de payload externo | Mapper puro |
| leitura combinando módulos | Reporting Query Object |

## Padrões proibidos

Não introduza:

- `ProcessEverythingService` ou outro Service que controle um módulo inteiro;
- Service que apenas executa `Model.find`;
- Query Object que grava, enfileira ou chama HTTP;
- Presenter que consulta banco ou decide regra legislativa;
- controller com regra, transação ou integração externa;
- callback de model que dispara fluxo cross-module oculto;
- acesso direto a model interno de outro módulo;
- associação cross-module criada apenas por conveniência de uma tela;
- enum fechado para valores controlados pela fonte sem estratégia de novidade;
- fallback que converte erro externo em `[]`, `false` ou sucesso;
- teste padrão dependente da internet;
- abstração base criada antes de haver repetição comprovada.

## Definição de pronto para issues e PRs

Antes de concluir uma implementação, confirme:

- [ ] O módulo proprietário está explícito no namespace e nos caminhos.
- [ ] A direção das dependências não viola este documento.
- [ ] Escrita passa por Service; leitura complexa passa por Query Object.
- [ ] Presenter, se existir, não consulta banco nem contém regra de negócio.
- [ ] Controller e Job permanecem finos.
- [ ] HTTP ocorre fora da transação.
- [ ] A operação é idempotente e possui índices apropriados.
- [ ] Limitações semânticas da Câmara estão preservadas.
- [ ] Testes focados cobrem sucesso, falha e casos desconhecidos.
- [ ] `bin/ci` foi executado ou a limitação foi registrada no PR.
- [ ] Documentação, exemplos, variáveis, migrations e runbooks foram atualizados.
- [ ] O PR explica risco, observabilidade e rollback.

Quando uma issue contradizer estas regras, não implemente silenciosamente a
contradição. Registre o conflito, proponha a correção da issue e preserve a
decisão arquitetural mais recente aprovada no repositório.
