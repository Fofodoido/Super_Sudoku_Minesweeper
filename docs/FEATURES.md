# Campo Minado — funcionalidades

Lista do que o produto faz e em que camada cada coisa vive. A divisão segue a
força de cada linguagem:

- **Prolog** é a autoridade da partida: gera as minas, aplica as regras, guarda
  as sessões e decide vitória ou derrota.
- **Elm** guarda só a projeção pública recebida do servidor, controla
  requisições, carregamento e erros, e desenha a interface.
- **HTML/CSS** cuidam da apresentação, do foco visível e do layout responsivo.

O cliente nunca recebe as minas enquanto a partida está em andamento, então não
há como trapacear lendo a resposta da API.

Situação em 23/11/2026: servidor, regras, API, cliente Elm e interface
integrados e testados. Os módulos do Super Sudoku foram retirados do produto.

## Regras do jogo (implementado em Prolog)

| Funcionalidade | Como funciona | Onde |
| --- | --- | --- |
| Três dificuldades | fácil 9×9 com 10 minas, médio 16×16 com 40, difícil 16×30 com 99 | `preset/4` em `board.pl` |
| Primeiro clique seguro | as minas só são sorteadas na primeira revelação, excluindo a célula clicada | `ensure_mines/7` em `game.pl`, `generate_mines/5` em `board.pl` |
| Números | cada célula segura revelada mostra quantas das até 8 vizinhas são minas | `adjacent_mines/5` em `board.pl` |
| Expansão | revelar uma célula 0 abre a região vazia conectada e sua borda numerada, em largura, sem abrir bandeiras | `expand_safe/7` em `game.pl` |
| Bandeiras | alternam em célula oculta, inclusive antes do primeiro clique; bloqueiam a revelação | `apply_valid_action/4` em `game.pl` |
| Vitória | todas as células seguras reveladas; bandeiras não são obrigatórias | `apply_valid_action/4` em `game.pl` |
| Derrota | revelar uma mina; a mina clicada é marcada como detonada | `apply_valid_action/4` em `game.pl` |
| Fim de partida | após vitória ou derrota nenhuma ação altera o tabuleiro | `execute_action/3` em `game.pl` |
| Projeção pública | em partida ativa só saem `hidden`, `flagged` e `revealed` com número; no fim aparecem `mine`, `exploded` e bandeiras erradas | `public_cells/2` em `game.pl` |

O primeiro clique é seguro, mas não há garantia de área inicial vazia nem de
partida resolvível sem adivinhação.

## Servidor e sessões (implementado em Prolog)

| Funcionalidade | Como funciona | Onde |
| --- | --- | --- |
| API JSON | `POST /api/games`, `GET /api/games/:id`, `POST /api/games/:id/actions`; erros padronizados | `server.pl`, [API.md](API.md) |
| Sessões em memória | identificador UUID v4, expiração após 2 h sem atividade, limite de 1.000 partidas | `sessions.pl` |
| Uma ação por vez | ações da mesma partida são serializadas por mutex | `session_mutex/2` em `sessions.pl` |
| Revisão | número que cresce a cada mudança, para o cliente detectar respostas antigas | `game_state/10` em `game.pl` |

Reiniciar o servidor perde todas as partidas: não há persistência, contas nem
autenticação.

## Cliente (implementado em Elm)

| Funcionalidade | Como funciona | Onde |
| --- | --- | --- |
| Nova partida e reinício | escolher a dificuldade cria uma partida; reiniciar cria outra na mesma dificuldade | `startNewGame` em `Main.elm` |
| Uma ação por vez | enquanto há requisição pendente (`PendingRequest`), novas ações são bloqueadas | `sendPlayerAction`, `isBusy` em `Main.elm` |
| Validação antes de enviar | não envia revelação em célula com bandeira nem ação em partida encerrada | `Game.canReveal`, `Game.canToggleFlag` |
| Timeout e falha de rede | a ação não é repetida; o cliente consulta `GET` e só libera o tabuleiro com o estado confirmado; se o `GET` também falhar, oferece sincronizar de novo | `handleActionResult`, `handleSyncResult`, estado `SyncFailed` |
| Respostas atrasadas | cada requisição leva um `requestToken`; respostas de token ou partida antiga são ignoradas | `update` em `Main.elm` |
| Sessão perdida | 404 `game_not_found` mostra aviso, para o cronômetro e oferece novo jogo | `Api.isSessionLost`, estado `SessionLost` |
| Validação do JSON | decoders rejeitam dificuldade/status desconhecidos, contagem de células errada, coordenadas fora da grade e minas expostas em partida ativa | `snapshotDecoder`, `validateSnapshot` em `Api.elm` |
| Contador e cronômetro | minas restantes = minas − bandeiras; cronômetro local começa na primeira revelação confirmada e para no fim | `Game.remainingMines`, `subscriptions` |

## Interface (Elm + HTML/CSS)

- **Mouse:** clique revela; botão direito marca/desmarca bandeira.
- **Toque:** botão de modo (revelar ↔ bandeira) troca o que o toque faz; nenhum
  toque longo é necessário.
- **Teclado:** setas ou WASD movem o foco na grade; Home/End e PageUp/PageDown
  vão às bordas; Enter/Espaço fazem a ação do modo atual; `R` revela; `F` marca
  bandeira. Atalhos globais: `1`/`2`/`3` dificuldade, `N` novo jogo, `G` foca a
  grade, `M` troca o modo, `U` sincroniza após falha, `?` abre a ajuda, Esc fecha.
- **Acessibilidade:** cada célula tem rótulo em português (linha e coluna a
  partir de 1, estado e número); estados distinguidos por ícone, não só por cor;
  anúncios em região `aria-live`.
- **Fim de partida:** na derrota, mina detonada, minas restantes, bandeiras
  certas e bandeiras erradas aparecem distintas (`Board.visualKind`).
- **Responsivo:** a grade difícil (16×30) rola horizontalmente em telas
  estreitas; a densidade das células se ajusta à dificuldade
  (`Board.boardDensityClass`).

## Fora do MVP

Ranking, contas, multiplayer, desfazer, dicas/solver, desafio diário, variantes
e abertura por acorde (chording).
