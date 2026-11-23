# Campo Minado — explicação dos conceitos usados

Este documento liga os tópicos da disciplina ao código do Campo Minado que
existe hoje. Só aparece aqui o que está de fato no código; o que depende de
frentes ainda não integradas está marcado como pendente.

A versão anterior deste arquivo descrevia o Super Sudoku e continua no
histórico Git (`git log -- docs/EXPLICACAO.md`).

## Visão geral

```
Navegador (Elm)  ──JSON──▶  server.pl  ──▶  sessions.pl  ──▶  game.pl  ──▶  board.pl
  projeção pública           HTTP/erros      sessões/mutex     regras        geometria
```

- `backend/minesweeper/board.pl`: geometria retangular, vizinhança, sorteio
  das minas e contagem de minas vizinhas. Não guarda estado.
- `backend/minesweeper/game.pl`: a partida como um termo imutável
  `game_state/10` e as transições `reveal` e `toggle_flag`. Cada ação devolve
  um estado novo; nada é alterado no lugar.
- `backend/minesweeper/sessions.pl`: o único lugar com estado mutável. Associa
  cada UUID ao `game_state` atual, com expiração e exclusão mútua.
- `backend/server.pl`: traduz HTTP/JSON para chamadas às sessões e os
  resultados `ok/1` e `error/1` para respostas e códigos HTTP.
- Elm (`frontend/src`): pendente das frentes 04 e 05; hoje o bundle ainda é o
  do Sudoku.

A separação faz com que as regras sejam testadas sem servidor (`game.pl` é
puro) e que o servidor seja a única fonte da verdade: o cliente recebe só o que
pode ser mostrado.

## Mapa: tópico → onde está no código

| Tópico | Onde está |
| --- | --- |
| Fatos, regras e consultas | `preset/4` são fatos; `valid_cell/3` e `neighbors/4` são regras; `preset(D, R, C, M)` enumera as dificuldades nos testes (`forall(preset(...))`) |
| Termos compostos como dados | `cell(Row, Col)`; o estado `game_state/10`; resultados `ok(Game)` e `error(Reason)`; `api_error(Status, Code, Message)` em `server.pl` |
| Unificação e casamento de padrões | cláusulas de `parse_action/3` (`reveal(cell(R,C))`, `reveal(R, C)`, dict JSON); `ensure_mines/7` distingue `ungenerated` de `generated(Mines)` pela cabeça; `reply_action_result/1` escolhe a resposta HTTP por padrão |
| Estados inválidos não representáveis | `ungenerated` versus `generated([])`: "minas ainda não sorteadas" não se confunde com "nenhuma mina"; `Exploded` é `none` ou `cell(R,C)` |
| Aritmética com `is` e comparação | limites em `neighbors/4` (`max/2`, `min/2`); `SafeTarget is Rows * Cols - MineCount` e `=:=` na vitória |
| Listas e recursão | `expand_safe/7`: busca em largura recursiva com a fila como lista (`append(Rest, NewCells, Next)`) |
| Geração com `findall/3` e `between/3` | `cells/3` e `neighbors/4` geram coordenadas por retrocesso e coletam as soluções |
| Ordem superior | `maplist/2,3` em validações e na projeção (`public_cells/2`); `include/3` em `adjacent_mines/5`; `exclude/3` em `expand_safe/7` |
| Conjuntos ordenados | `library(ordsets)`: reveladas e bandeiras como `ordsets`; `ord_union/3`, `ord_memberchk/2`, `ord_disjoint/2` em `game.pl` |
| Corte, `->` e negação por falha | `execute_action/3` com if-then-else aninhado; `cell_blocked/4` com `!`; `\+ game_session(Id, _, _)` em `unique_session_id/1` |
| Gerar e testar com `repeat` | `unique_session_id/1`: gera UUIDs até achar um que ainda não existe |
| Aleatoriedade | `random_permutation/2` em `generate_mines/5`: embaralha as candidatas e fica com as `MineCount` primeiras |
| Imutabilidade e transições puras | `game_action/3` recebe `Game0` e devolve `ok(Game)`; o estado anterior continua válido (usado para responder erro sem alterar a partida) |
| Base de dados dinâmica | `:- dynamic game_session/3` com `assertz/1` e `retract/1` em `sessions.pl` |
| Concorrência | `with_mutex/2`: um registro global e 256 mutexes particionados por `term_hash/2` do ID, para serializar ações da mesma partida |
| Exceções | `throw(api_error(...))` e `catch/3` em `handle_games/1`; erro inesperado vira 500 sem detalhes |
| Dicts e JSON | `public_snapshot/3` monta dicts (`_{...}`, `.put/2`); `http_read_json/3` e `reply_json_dict/2` em `server.pl` |
| Módulos | `module/2` com exportações explícitas em `board.pl`, `game.pl` e `sessions.pl`; `game_state/10` é opaco fora de `game.pl` |
| Integração com outras linguagens | Prolog serve HTTP/JSON consumido pelo Elm (`server.pl`, [API.md](API.md)) |
| Testes | `plunit` em `backend/tests`, com `forall/1` para repetir um teste por dificuldade e `setup`/`cleanup` subindo o servidor real |

### Elm (pendente: frentes 04 e 05)

Quando o cliente for integrado, esta seção deve mapear: TEA (`Model`,
`update`, `view`), tipos algébricos para estado da partida e das requisições,
`Maybe`/`Result`, decoders e encoders JSON do snapshot, efeitos HTTP com
`Cmd`, controle de uma requisição pendente por vez e descarte de respostas de
partida antiga. Nada disso está escrito ainda.

## Conceitos que o Campo Minado não usa

O Super Sudoku usava CLP(FD), meta-interpretador e um exemplo de Prolog chamado
do Python (janus). O Campo Minado não precisa de nenhum deles: as regras são
contagem de vizinhos e busca em largura. Esses módulos (`backend/sudoku`,
`backend/python/exemplo_janus.py`) saem do produto ativo na integração final.

Se a disciplina exigir algum desses tópicos, isso precisa ser confirmado antes
de ser prometido. Dicas com CLP(FD) estão previstas apenas como extensão após o
MVP ([PLANO_CAMPO_MINADO.md](PLANO_CAMPO_MINADO.md)).

## Como verificar

```sh
make test
make test-acceptance
```

Detalhes, versões e matriz de cenários em [ACEITE.md](ACEITE.md).
