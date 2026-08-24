# Tesa

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

## Licença

Este projeto é distribuído sob a [GNU Affero General Public License v3.0 ou posterior](LICENSE). Versões modificadas disponibilizadas para interação por rede devem oferecer aos usuários acesso ao código-fonte correspondente, conforme os termos da AGPL.
