# Campo Minado — Prolog + Elm

Projeto de Campo Minado web desenvolvido com SWI-Prolog e Elm, com interface em português e HTML/CSS.

**Estado atual:** a base Prolog de geometria, geração, motor de regras, sessões em memória e API HTTP de Campo Minado está implementada e testada. O bundle compilado ainda apresenta a interface do Sudoku original; o cliente e a interface de Campo Minado permanecem nas respectivas frentes.

## Escopo planejado

- Três dificuldades: fácil (9x9, 10 minas), médio (16x16, 40 minas) e difícil (16x30, 99 minas).
- Primeiro clique seguro, revelação de células e expansão de áreas vazias.
- Bandeiras, contador de bandeiras restantes e cronômetro local.
- Vitória ao revelar todas as células seguras e derrota ao revelar uma mina.
- Nova partida, reinício e controles por mouse, teclado e toque.
- Interface responsiva com foco visível e estados identificáveis sem depender apenas de cor.

Ranking, contas, multiplayer, desfazer e dicas ficam fora do MVP. O primeiro clique seguro não garante que toda partida possa ser resolvida sem adivinhação.

## Arquitetura planejada

| Camada | Responsabilidade |
| --- | --- |
| SWI-Prolog | Geometria, geração de minas, regras, transições e resultado da partida |
| HTTP/JSON em Prolog | API e sessões em memória; envio apenas do estado público ao cliente |
| Elm | Modelo da interface, comunicação HTTP, eventos, carregamento e tratamento de erros |
| HTML/CSS | Apresentação responsiva e controles acessíveis |

O servidor guarda as minas e valida as jogadas. As sessões expiram após duas horas de inatividade e são perdidas ao reiniciar o servidor. Os endpoints implementados são `POST /api/games`, `GET /api/games/:id` e `POST /api/games/:id/actions`; o contrato completo está em [docs/API.md](docs/API.md).

O [plano de migração](docs/PLANO_CAMPO_MINADO.md) detalha o contrato proposto, as regras, as dependências entre frentes e os critérios de conclusão.

## Equipe e responsabilidades

| Frente | Integrante | GitHub | Responsabilidade | Revisor obrigatório do PR |
| --- | --- | --- | --- | --- |
| 01 | Gustavo Xavier Evangelista | [guxvr](https://github.com/guxvr) | Migração inicial do projeto, geometria e geração do tabuleiro em Prolog | Rodrigo |
| 02 | Rodrigo Henrique Donato de Souza | [fofodoido](https://github.com/fofodoido) | Motor de regras e transições em Prolog | Davi |
| 03 | Davi Araujo Bady Casseb | [dcasseb](https://github.com/dcasseb) | Contrato JSON, API HTTP e sessões | Mateus |
| 04 | Mateus de Siqueira Silva | [siqueira-prog](https://github.com/siqueira-prog) | Modelo Elm, cliente HTTP e ciclo da partida | Carlos |
| 05 | Carlos Eduardo Mendes de Mesquita | [CarlosEduardoMendesdeMesquita](https://github.com/CarlosEduardoMendesdeMesquita) | Tabuleiro e interface acessível e responsiva | Gabriel |
| 06 | Gabriel Basto Bertolazi | [Bertolazi](https://github.com/Bertolazi) | Integração, CI, testes de aceite e documentação | Gustavo |

Todo PR deve ser revisado e aprovado pelo responsável pela frente seguinte antes do merge, na sequência circular **01 → 02 → 03 → 04 → 05 → 06 → 01**. O autor solicita a revisão e resolve as alterações pedidas; a aprovação deve ficar registrada no GitHub. Cada integrante mantém os testes da própria frente.

## Etapas de entrega

1. Alinhar os contratos Prolog, JSON e Elm e preparar a estrutura da migração.
2. Integrar o fluxo mínimo: criar partida, revelar célula e exibir o número retornado pelo Prolog.
3. Completar regras, bandeiras, dificuldades, cronômetro e recuperação de erros.
4. Validar acessibilidade, integração, testes e documentação; retirar o legado do produto ativo.

## Como executar

O servidor já expõe a API de Campo Minado e continua servindo o bundle estático existente, que será substituído pelas frentes de cliente e interface.

Requisitos:

- [SWI-Prolog](https://www.swi-prolog.org/) **10 ou superior** (o CI usa 10.0.2). A série 9 não carrega `library(json)`, usada nos testes HTTP.
- [Node.js](https://nodejs.org/) 18+ apenas para instalar as ferramentas Elm. As versões de [Elm](https://elm-lang.org/) 0.19.1 e `elm-test` ficam fixadas em `frontend/package.json`; não é preciso instalação global.
- `make` é opcional.

As partidas ficam só na memória do servidor: **reiniciar o servidor perde todas as partidas em andamento**, e uma partida sem atividade por duas horas expira.

### Com make

```sh
make deps
make run
make run PORT=3000
make test
make ci
```

Outros alvos: `make test-minesweeper` (suítes de Campo Minado, sem o legado), `make test-acceptance` (fluxos integrados via HTTP), `make check-bundle` e `make help`.

### Sem make

```sh
cd frontend
npm ci
npx elm make src/Main.elm --optimize --output=public/elm.js
cd ..
swipl backend/server.pl 8080
```

O bundle `frontend/public/elm.js` está versionado e corresponde ao fonte; para só executar, basta `swipl backend/server.pl 8080` e abrir `http://localhost:8080`.

Testes sem make:

```sh
for t in backend/tests/test_*.pl; do swipl -g run_tests -t halt "$t" || exit 1; done
```

`test_sudoku.pl` é a suíte legada e sai junto com o Sudoku na integração final.

### Integração contínua

O workflow [`.github/workflows/ci.yml`](.github/workflows/ci.yml) roda em todo PR e em `main`: testes Prolog no contêiner `swipl:10.0.2` e, no job Elm, instalação fixada, conferência de que `elm.js` corresponde ao fonte e `elm-test`. Comandos, versões, matriz de cenários e procedimento de aceite no navegador estão em [docs/ACEITE.md](docs/ACEITE.md).

## Documentação

O [mapa de migração e integração](docs/MIGRACAO_CAMPO_MINADO.md) identifica os módulos a substituir, os pontos de integração e as responsabilidades pela retirada final do legado.

O [contrato do tabuleiro](docs/MINESWEEPER_BOARD.md) documenta os predicados implementados em `backend/minesweeper/board.pl` para integração com o motor.

O [contrato do motor](docs/MINESWEEPER_GAME.md) documenta os predicados, ações, erros e projeção pública implementados em `backend/minesweeper/game.pl` para integração com a API HTTP.

O [contrato da API](docs/API.md) documenta endpoints, snapshots, erros, sessões e as fixtures JSON compartilhadas com o cliente Elm.

O [aceite integrado](docs/ACEITE.md) registra versões, comandos, a matriz de cenários com a suíte que cobre cada um e o procedimento de aceite no navegador.

O documento principal do novo projeto é o [plano de Campo Minado](docs/PLANO_CAMPO_MINADO.md). [FEATURES.md](docs/FEATURES.md) lista as funcionalidades por camada e [EXPLICACAO.md](docs/EXPLICACAO.md) liga os tópicos da disciplina ao código; as seções de Elm serão completadas quando o cliente for integrado.
