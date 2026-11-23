# API HTTP v1 — Campo Minado

Este documento é o contrato compartilhado entre o motor Prolog, a camada HTTP
e o cliente Elm. A API usa JSON, coordenadas de base zero e snapshots completos
da projeção pública de cada partida.

## Convenções

- Base: `/api`.
- Requests e responses usam `Content-Type: application/json`.
- Coordenadas: `row` e `col`, ambas iniciando em zero.
- Dificuldades: `easy`, `medium` e `hard`.
- Status: `ready`, `playing`, `won` e `lost`.
- Os identificadores são UUIDs opacos. O cliente não deve extrair significado
  deles.
- Células são sempre retornadas em ordem de linha e depois coluna.
- Cada resposta bem-sucedida contém o snapshot completo, não um delta.

## Snapshot público

```json
{
  "id": "00000000-0000-4000-8000-000000000001",
  "difficulty": "easy",
  "rows": 9,
  "cols": 9,
  "mineCount": 10,
  "status": "ready",
  "revision": 0,
  "cells": [
    { "row": 0, "col": 0, "state": "hidden" }
  ]
}
```

Dimensões por dificuldade:

| difficulty | rows | cols | mineCount |
|---|---:|---:|---:|
| `easy` | 9 | 9 | 10 |
| `medium` | 16 | 16 | 40 |
| `hard` | 16 | 30 | 99 |

`revision` começa em zero e cresce em um somente quando uma ação altera a
partida. Revelar novamente uma célula já revelada devolve o mesmo snapshot e
não incrementa a revisão. GET nunca altera a revisão.

### Estados de célula

| state | Campos adicionais | Uso |
|---|---|---|
| `hidden` | nenhum | Célula ainda oculta |
| `flagged` | nenhum | Célula marcada pelo jogador |
| `revealed` | `adjacentMines` de 0 a 8 | Célula segura revelada |
| `mine` | nenhum | Mina mostrada após o encerramento |
| `exploded` | nenhum | Mina que causou a derrota |

Enquanto o status for `ready` ou `playing`, a resposta nunca contém minas,
semente, estado `mine`/`exploded` ou `adjacentMines` em célula oculta ou marcada.

Quando uma partida termina em derrota, uma bandeira colocada em célula segura
permanece com `state: "flagged"`. O cliente identifica a bandeira incorreta pela
combinação de `status: "lost"` e `state: "flagged"`. Minas corretamente marcadas
passam a `mine`; a mina selecionada passa a `exploded`.

## Criar partida

`POST /api/games`

Request:

```json
{ "difficulty": "easy" }
```

Resposta: `201 Created` com snapshot em `ready`, revisão zero e todas as
células ocultas. As minas ainda não foram geradas.

## Consultar partida

`GET /api/games/:id`

Resposta: `200 OK` com o snapshot atual. Uma consulta válida renova o prazo de
inatividade da sessão, mas não altera `revision`.

## Aplicar ação

`POST /api/games/:id/actions`

Revelar:

```json
{ "action": "reveal", "row": 4, "col": 4 }
```

Alternar bandeira:

```json
{ "action": "toggle_flag", "row": 0, "col": 0 }
```

Resposta: `200 OK` com o snapshot resultante. A primeira revelação válida gera
as minas excluindo a célula selecionada. Bandeiras podem ser alternadas antes
da primeira revelação sem gerar minas.

Uma única ação é executada por vez em cada partida. Partidas distintas podem
ser processadas em paralelo; uma colisão na partição interna de locks apenas
reduz o paralelismo, sem misturar estados. Como `toggle_flag` não é idempotente, o cliente não deve
repeti-la automaticamente após timeout; deve consultar GET para recuperar o
estado confirmado.

## Erros

Todos os erros da árvore `/api/games` usam:

```json
{
  "error": {
    "code": "invalid_cell",
    "message": "Coordenadas ausentes, inválidas ou fora do tabuleiro"
  }
}
```

| HTTP | code | Condição |
|---:|---|---|
| 400 | `invalid_json` | Corpo não é JSON válido |
| 400 | `invalid_request` | Corpo não é um objeto JSON |
| 400 | `invalid_difficulty` | Dificuldade ausente ou desconhecida |
| 400 | `invalid_action` | Ação ausente ou desconhecida |
| 400 | `invalid_cell` | Coordenada ausente, não inteira ou fora dos limites |
| 404 | `game_not_found` | ID ausente, inválido ou sessão expirada |
| 404 | `endpoint_not_found` | Subrota desconhecida |
| 405 | `method_not_allowed` | Método não suportado pela rota |
| 409 | `game_over` | Ação enviada após vitória ou derrota |
| 409 | `cell_flagged` | Tentativa de revelar célula marcada |
| 409 | `cell_revealed` | Tentativa de marcar célula revelada |
| 411 | `length_required` | Request mutante sem `Content-Length` |
| 413 | `payload_too_large` | Corpo maior que 4.096 bytes |
| 503 | `session_limit_reached` | Limite de sessões ativas atingido |
| 500 | `internal_error` | Falha inesperada; detalhes não são enviados ao cliente |

Entrada inválida (`invalid_action`/`invalid_cell`) é classificada antes do
estado encerrado da partida. Sessões inexistentes, UUIDs malformados e sessões
expiradas têm a mesma resposta para não revelar a existência anterior de IDs.

## Sessões

- Armazenamento somente em memória; reiniciar o servidor remove as partidas.
- Expiração após 7.200 segundos de inatividade.
- A sessão expira quando `agora - últimoAcesso >= 7200`.
- GET válido e POST que encontra uma sessão válida renovam a atividade, mesmo
  se a ação resultar em 400 ou 409. JSON ilegível não renova a sessão.
- Limite padrão: 1.000 sessões ativas.
- Antes de aplicar o limite, sessões expiradas são removidas.
- Não há autenticação, persistência, ranking ou multiplayer no MVP.

## Fixtures compartilhadas

Os exemplos consumíveis por Prolog e Elm ficam em
`backend/tests/fixtures/api/`:

- `create-easy.request.json`
- `reveal.request.json`
- `toggle-flag.request.json`
- `ready-easy.response.json`
- `playing-easy.response.json`
- `lost-easy.response.json`
- `invalid-cell.error.json`

Os IDs das fixtures são determinísticos apenas para comparação. A API real
sempre gera um novo UUID. Os snapshots das fixtures devem passar os mesmos
decoders e invariantes verificados nas respostas reais.
