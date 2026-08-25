<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/branding/diafania-claritas-logo-inverse.svg">
  <source media="(prefers-color-scheme: light)" srcset="assets/branding/diafania-claritas-logo.svg">
  <img alt="Diafania Claritas: o Congresso Nacional observado por um olho" src="assets/branding/diafania-claritas-logo.svg" width="560">
</picture>

# Tesa

[![CI](https://github.com/Araendy-Aratyba/tesa/actions/workflows/ci.yml/badge.svg)](https://github.com/Araendy-Aratyba/tesa/actions/workflows/ci.yml)
[![License: AGPL-3.0-or-later](https://img.shields.io/badge/license-AGPL--3.0--or--later-blue.svg)](LICENSE)

Aplicação Rails para trabalhar com dados legislativos da Câmara dos Deputados, usando o cliente [CongregaPlenum](https://github.com/Araendy-Aratyba/CongregaPlenum).

## Stack

- Ruby 3.4.6, gerenciado com rbenv
- Rails 8.1.3.1
- PostgreSQL
- Hotwire: Turbo e Stimulus com Importmap
- Tailwind CSS 4
- Solid Cache, Solid Queue e Solid Cable
- RSpec, FactoryBot, Capybara e Selenium
- Herb para análise e lint de templates HTML+ERB

## Preparação local

Instale e selecione o Ruby:

```bash
rbenv install -s 3.4.6
rbenv local 3.4.6
gem install bundler
```

Prepare dependências e banco de dados:

```bash
bin/setup --skip-server
pnpm install --frozen-lockfile
```

O Dev Container inclui Ruby 3.4.6, Node.js, pnpm e um serviço PostgreSQL. Ao abri-lo, o comando de preparação é executado automaticamente.

## Desenvolvimento

Inicie Rails e o watcher do Tailwind:

```bash
bin/dev
```

A aplicação estará disponível em <http://localhost:3000>.

## Integração com a Câmara

O Tesa mantém a URL oficial da API de Dados Abertos configurada pela
CongregaPlenum. Apenas os parâmetros operacionais podem ser ajustados por
variáveis de ambiente:

| Variável | Padrão | Finalidade |
| --- | ---: | --- |
| `CAMARA_API_TIMEOUT` | `30` | timeout de abertura e leitura, em segundos |
| `CAMARA_API_RETRIES` | `3` | novas tentativas para falhas transitórias |
| `CAMARA_API_RETRY_DELAY` | `1.0` | espera inicial entre tentativas, em segundos |
| `CAMARA_API_RATE_LIMIT_DELAY` | `0.1` | intervalo entre páginas, em segundos |

A aplicação interpreta horários locais no fuso de Brasília e persiste instantes
em UTC. A API é pública e não exige token ou outra credencial.

Para diagnosticar manualmente a versão instalada e buscar uma única votação na
API oficial, execute o smoke test abaixo. Este comando usa a rede de propósito e
não faz parte da suíte automatizada:

```bash
bin/rails runner '
  puts "CongregaPlenum #{CongregaPlenum::VERSION}"
  voting = CongregaPlenum::VotingsService.fetch_list(items_per_page: 1).first
  abort "Nenhuma votação retornada pela API oficial" unless voting
  puts "Votação #{voting.fetch("id")}"
'
```

O identificador exibido deve ser tratado como string e pode ser alfanumérico,
por exemplo `2355754-35`; ele não deve ser convertido para número.

## Desenvolvimento com Docker Compose

O Compose inicia a aplicação com `Dockerfile.dev`, PostgreSQL e Redis. Construa a imagem e suba os serviços:

```bash
docker compose build app
docker compose up
```

A aplicação estará disponível em <http://localhost:3000>. PostgreSQL e Redis também são publicados no host, respectivamente nas portas `5432` e `6379`, mas apenas na interface local. Para alterar as portas sem editar o arquivo:

```bash
APP_PORT=3001 POSTGRES_PORT=5433 REDIS_PORT=6380 docker compose up
```

Execute comandos Rails e a suíte de testes em containers descartáveis:

```bash
docker compose run --rm app bin/rails console
docker compose run --rm -e RAILS_ENV=test app bin/rspec
```

Encerre os serviços mantendo os dados persistidos:

```bash
docker compose down
```

Os volumes nomeados preservam gems, módulos JavaScript, PostgreSQL e Redis. `docker compose down --volumes` também remove esses dados.

O Compose disponibiliza `REDIS_URL=redis://redis:6379/0` para integrações que precisem de Redis. Os adaptadores padrão do Rails 8 continuam usando Solid Cache, Solid Queue e Solid Cable.

## Imagem de produção

O `Dockerfile` da raiz gera uma imagem multi-stage, pré-compila os assets e executa a aplicação como usuário sem privilégios:

```bash
docker build --file Dockerfile --tag tesa:production .
```

Em produção, forneça as credenciais do Rails e as URLs dos bancos fora da imagem, por variáveis de ambiente ou pelo gerenciador de segredos da plataforma de deploy.

## Qualidade e testes

```bash
bin/rspec
bin/rubocop
pnpm lint:erb
bin/brakeman --quiet --no-pager
bin/bundler-audit
bin/importmap audit
```

Para executar a mesma sequência consolidada do CI:

```bash
bin/ci
```

## Contribuindo

Contribuições são bem-vindas. Antes de começar, consulte o
[guia de contribuição](CONTRIBUTING.md), o [Código de Conduta](CODE_OF_CONDUCT.md)
e a [Política de Segurança](SECURITY.md). Dúvidas e propostas iniciais podem ser
levadas às [discussões do projeto](https://github.com/Araendy-Aratyba/tesa/discussions).

Toda mudança deve ser enviada por pull request. A branch `main` exige os checks
do CI e não aceita commits diretos.

## Licença

Este projeto é distribuído sob a [GNU Affero General Public License v3.0 ou posterior](LICENSE). Versões modificadas disponibilizadas para interação por rede devem oferecer aos usuários acesso ao código-fonte correspondente, conforme os termos da AGPL.
