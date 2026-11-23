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

Situação em 23/11/2026: servidor, regras e API implementados e testados; cliente
Elm e interface de Campo Minado pendentes das frentes 04 e 05. O bundle servido
ainda é a interface do Sudoku.

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

## Interface (pendente: frentes 04 e 05)

Planejado em [PLANO_CAMPO_MINADO.md](PLANO_CAMPO_MINADO.md):

- Nova partida, reinício na mesma dificuldade, contador de bandeiras restantes e
  cronômetro local que começa na primeira revelação confirmada.
- Mouse, teclado e modo explícito de bandeira para toque.
- Uma requisição de ação por vez; após timeout, consultar o estado com GET em vez
  de repetir a ação; ignorar respostas de partida antiga depois de novo jogo.
- Estados distinguíveis sem depender só de cor; grade difícil utilizável em
  celular com rolagem.

Esta seção será substituída pela descrição real quando o cliente for integrado.

## Fora do MVP

Ranking, contas, multiplayer, desfazer, dicas/solver, desafio diário, variantes
e abertura por acorde (chording).
