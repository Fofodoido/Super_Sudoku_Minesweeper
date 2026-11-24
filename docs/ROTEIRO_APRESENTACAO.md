# Roteiro da Apresentação Oral — Campo Minado (Prolog + Elm)

- **Material:** [docs/apresentacao.pdf](apresentacao.pdf) (18 slides)
- **Duração total alvo:** 15 minutos (com demonstração ao vivo e espaço para perguntas)
- **Equipe:** Grupo SuperSMs (`Gustavo`, `Rodrigo`, `Davi`, `Mateus`, `Carlos`, `Gabriel`)

---

## Distribuição de tempo e falas

| Bloco | Slides | Duração | Responsável | Foco principal |
|---|---|---:|---|---|
| 1. Abertura, problema e organização | 1–3 | 1,5 min | Gabriel Basto Bertolazi | Capa, regras do Campo Minado e divisão das 6 frentes |
| 2. Arquitetura e domínio/geração Prolog | 4–5 | 2,5 min | Gustavo Xavier Evangelista | Separação cliente/servidor, `board.pl` e primeiro clique seguro |
| 3. Motor de regras e expansão BFS | 6–7 | 2,5 min | Rodrigo Henrique Donato de Souza | Máquina de estados `game_state/10`, `expand_safe/7` e `public_snapshot/3` |
| 4. Contrato JSON, API HTTP e sessões | 8–10 | 2,5 min | Davi Araujo Bady Casseb | Snapshot público sem vazamento, rotas REST, erros e mutex por sessão |
| 5. Modelo algébrico e ciclo Elm | 11–12 | 2 min | Mateus de Siqueira Silva | Custom types, `validateSnapshot` e recuperação após falha de rede |
| 6. Interface acessível e demonstração ao vivo | 13–15 | 2,5 min | Carlos Eduardo Mendes de Mesquita | WAI-ARIA, teclado/toque, fluxo completo e demo rodando em `localhost:8080` |
| 7. Qualidade, limites e fechamento | 16–18 | 1,5 min | Gabriel Basto Bertolazi | Suítes Prolog/Elm, `elm-format`, validador, limitações e perguntas |

---

## Roteiro detalhado por slide e pontos de código (compreensão)

### Bloco 1 — Gabriel Basto Bertolazi (`1,5 min` · Slides 1 a 3)
- **Slide 1 (Capa):** Apresentar o tema (**Campo Minado em SWI-Prolog + Elm**) e os integrantes da equipe SuperSMs.
- **Slide 2 (Problema):** Explicar os três presets (`easy` 9×9 / 10 minas, `medium` 16×16 / 40 minas, `hard` 16×30 / 99 minas), primeiro clique sempre seguro, expansão de células zero, bandeiras e critérios de vitória/derrota.
- **Slide 3 (Organização):** Destacar a divisão em 6 frentes independentes ligadas por contratos claros e fluxo de revisão circular por PR (`01 → 02 → 03 → 04 → 05 → 06 → 01`).

### Bloco 2 — Gustavo Xavier Evangelista (`2,5 min` · Slides 4 e 5)
- **Slide 4 (Arquitetura):** Mostrar que o SWI-Prolog concentra 100% das regras e sessões (`board.pl`, `game.pl`, `sessions.pl`, `server.pl`), enquanto o Elm (`Main.elm`, `Api.elm`, `Game.elm`, `Board.elm`, `Explosion.elm`) consome apenas a projeção pública via JSON.
- **Slide 5 (Frente 01 — Geometria e geração):** Apontar `preset/4` (`backend/minesweeper/board.pl:24-26`), `neighbors/4` (`backend/minesweeper/board.pl:51`) usando `findall/3` + `between/3`, e `generate_mines/5` (`backend/minesweeper/board.pl:65`) excluindo `SafeCell` antes de sortear.

### Bloco 3 — Rodrigo Henrique Donato de Souza (`2,5 min` · Slides 6 e 7)
- **Slide 6 (Frente 02 — Motor de regras):** Explicar `game_state/10` (`ungenerated` vs `generated(Mines)`), o predicado puro `game_action/3` (`backend/minesweeper/game.pl:90`) retornando `ok(Game)` ou `error(Reason)`, bandeira antes do 1º clique e bloqueio em `won`/`lost`.
- **Slide 7 (Frente 02 — Expansão BFS):** Mostrar `expand_safe/7` (`backend/minesweeper/game.pl:177-188`) usando fila FIFO, `exclude/3` (`cell_blocked/4`) e `library(ordsets)` para abrir células `0` e sua borda numérica sem alterar bandeiras. Citar também `public_snapshot/3` (`backend/minesweeper/game.pl:251`), que omite minas e `adjacentMines` de células fechadas durante `ready`/`playing`.

### Bloco 4 — Davi Araujo Bady Casseb (`2,5 min` · Slides 8 a 10)
- **Slide 8 (Contrato JSON):** Detalhar o snapshot completo retornado a cada operação e a invariante de segurança (sem `mine`, `exploded` nem `adjacentMines` vazados durante a partida).
- **Slide 9 (API HTTP):** Apresentar as 3 rotas (`POST /api/games`, `GET /api/games/:id`, `POST /api/games/:id/actions`) em `backend/server.pl:67-80` e a precedência de validação (`400` antes de `409`, `404` uniforme para UUID inválido/inexistente/expirado).
- **Slide 10 (Sessões e concorrência):** Explicar UUID v4, expiração por inatividade (2 h), limite de 1.000 sessões (`503`) e particionamento com 256 mutexes (`session_mutex/2` em `backend/minesweeper/sessions.pl:202`, `apply_session_action/3` na linha `81`).

### Bloco 5 — Mateus de Siqueira Silva (`2 min` · Slides 11 e 12)
- **Slide 11 (Modelo Elm):** Mostrar `CellState` (`Revealed Int` impedindo leitura de contagem em célula fechada — `frontend/src/Game.elm:54`), `ScreenState` e `PendingRequest` (`frontend/src/Main.elm:56-68`) eliminando flags booleanas soltas.
- **Slide 12 (Ciclo da partida):** Explicar `cellStateDecoder` + `validateSnapshot` (`frontend/src/Api.elm:296-352`), descarte de respostas antigas via `requestToken`, recuperação via `GET` após timeout (sem reenviar `toggle_flag`) e cronômetro local em `subscriptions` (`frontend/src/Main.elm:701`).

### Bloco 6 — Carlos Eduardo Mendes de Mesquita (`2,5 min` · Slides 13 a 15)
- **Slide 13 (Interface acessível):** Destacar grade WAI-ARIA (`role="grid"`, `roving tabindex` em `frontend/src/Board.elm:669-826`), atalhos completos de teclado (`Setas`/`WASD`, `R`, `F`, `M`, `1/2/3`, `N`, `G`, `?`, `Esc`), modo Bandeira para toque e `VisualKind` (`frontend/src/Board.elm:271`) sem depender só de cor.
- **Slides 14 e 15 (Fluxo e Demonstração ao vivo):** Executar partida no navegador (`make run`): clicar no centro (1º clique seguro + expansão), marcar bandeira com botão direito, navegar e jogar pelo teclado (`F`/`R`), terminar e reiniciar com `N`, e abrir o modo Difícil 16×30. (Plano B: usar as capturas reais do Slide 14.)

### Bloco 7 — Gabriel Basto Bertolazi (`1,5 min` · Slides 16 a 18)
- **Slide 16 (Qualidade e testes):** Apresentar a cobertura automatizada: no slide constam as 4 suítes base (`60` testes `plunit`) e os `46` testes `elm-test`; ressaltar na fala que a suíte integrada final já soma **5 suítes Prolog (`65` testes + `66` subtestes, incluindo `test_minesweeper_acceptance.pl`)**, `46` testes Elm, checagem de `elm-format` no CI e **0 erros** no `make validar`.
- **Slide 17 (Limitações e próximos passos):** Sessões em memória volátil, ausência de chording/dicas CLP(FD)/persistência e priorização do fluxo ponta a ponta bem testado.
- **Slide 18 (Perguntas):** Exibir mapa de autoria para responder às perguntas técnicas e de compreensão individual sobre qualquer módulo.
