# Contribuindo com o Tesa

Obrigado por considerar uma contribuição. Correções, testes, documentação,
melhorias de acessibilidade e novas formas de explorar dados legislativos são
bem-vindos.

Ao participar, siga o [Código de Conduta](CODE_OF_CONDUCT.md). Vulnerabilidades
devem ser relatadas pelo processo privado descrito em [SECURITY.md](SECURITY.md),
nunca por uma issue pública.

## Antes de começar

- Pesquise as [issues existentes](https://github.com/Araendy-Aratyba/tesa/issues).
- Para mudanças grandes, abra primeiro uma issue ou discussão explicando o
  problema, a proposta e suas alternativas.
- Mantenha cada pull request pequeno e focado em uma única mudança.
- Nunca inclua credenciais, dados pessoais ou informações legislativas não
  públicas em código, testes, logs ou screenshots.

## Preparando o ambiente

O projeto usa Ruby 3.4.6, Rails 8.1.3.1, PostgreSQL, pnpm e Node.js. As versões
fixadas no repositório devem ser respeitadas.

Faça um fork, clone-o e crie uma branch descritiva:

```bash
git clone git@github.com:SEU_USUARIO/tesa.git
cd tesa
rbenv install -s 3.4.6
rbenv local 3.4.6
bin/setup --skip-server
pnpm install --frozen-lockfile
git switch -c fix/descricao-curta
```

Também é possível preparar todo o ambiente com Docker:

```bash
docker compose build app
docker compose up
```

Consulte o [README](README.md) para os demais comandos e opções de porta.

## Desenvolvimento

- Prefira Turbo e Stimulus a JavaScript global ou frameworks adicionais.
- Use HTML semântico, acessível e progressivamente aprimorado.
- Mantenha os controllers Stimulus pequenos e responsáveis apenas pelo
  comportamento da interface.
- Preserve Solid Cache, Solid Queue e Solid Cable, salvo decisão arquitetural
  discutida previamente.
- Mudanças de comportamento devem incluir testes RSpec.
- Use FactoryBot para dados de teste e evite dependência de serviços externos.
- Nunca altere silenciosamente o significado dos dados fornecidos pela Câmara
  dos Deputados; documente ambiguidades e limitações da fonte.

## Qualidade e testes

Antes de abrir um pull request, execute:

```bash
bin/ci
```

Para executar as verificações separadamente:

```bash
bin/rspec
bin/rubocop
pnpm lint:erb
bin/brakeman --quiet --no-pager
bin/bundler-audit
bin/importmap audit
```

Com Docker, execute os testes com:

```bash
docker compose run --rm -e RAILS_ENV=test app bin/rspec
```

## Commits e branches

Use nomes de branch curtos e descritivos, como `feat/filtros-de-votacao`,
`fix/erro-de-paginacao` ou `docs/instalacao`.

Escreva mensagens de commit curtas, em inglês, no modo imperativo. Exemplos:

```text
Add voting filters
Fix pagination cursor handling
Document Docker setup
```

Não faça commits diretamente na `main`. Toda mudança deve passar por pull
request e pelos checks obrigatórios do CI.

## Pull requests

Um pull request deve:

- explicar o problema, a solução e as decisões relevantes;
- relacionar a issue correspondente, quando existir;
- incluir testes e documentação proporcionais à mudança;
- incluir screenshots ou vídeos para mudanças visuais;
- passar em todos os checks obrigatórios;
- evitar alterações não relacionadas.

Contribuições são disponibilizadas sob a licença
[AGPL-3.0-or-later](LICENSE) do projeto.
