# Aceite integrado — Campo Minado (frente 06)

Responsável: Gabriel Basto Bertolazi (@Bertolazi), frente 06.

Este documento registra como o produto integrado é verificado: comandos
reproduzíveis, a matriz de cenários com a suíte que cobre cada um e o
procedimento de aceite no navegador. Cada frente mantém os testes da própria
área; aqui ficam os fluxos completos e o que só é verificável com tudo junto.

## Versões fixadas

| Ferramenta | Versão | Onde está fixada |
| --- | --- | --- |
| SWI-Prolog | 10.0.2 | `.github/workflows/ci.yml` (`container: swipl:10.0.2`) |
| Elm | 0.19.1 (npm `elm@0.19.1-5`) | `frontend/package.json` e `package-lock.json` |
| elm-test | 0.19.1-revision18 | `frontend/package.json` e `package-lock.json` |
| elm-explorations/test | 2.2.1 | `frontend/elm.json` (`test-dependencies`) |
| Node.js (só para instalar Elm) | 22 | `.github/workflows/ci.yml` |

SWI-Prolog 9.x não basta: `test_minesweeper_http.pl` usa `library(json)`, que
só existe a partir da série 10. Todas as suítes passam em 10.0.2 e 11.0.0.

## Comandos

Com `make`:

```sh
make deps
make ci
make test
make test-acceptance
make check-bundle
```

Sem `make`:

```sh
for t in backend/tests/test_*.pl; do swipl -g run_tests -t halt "$t" || exit 1; done
cd frontend
npm ci
npx elm make src/Main.elm --optimize --output=elm-stuff/elm.check.js
cmp elm-stuff/elm.check.js public/elm.js
npx elm-test
```

Sem SWI-Prolog instalado, a imagem oficial reproduz o ambiente do CI:

```sh
docker run --rm -v "$PWD":/w -w /w swipl:10.0.2 \
  sh -c 'for t in backend/tests/test_*.pl; do swipl -g run_tests -t halt "$t" || exit 1; done'
```

A compilação `elm make --optimize` do Elm 0.19.1 é determinística; por isso
`check-bundle` compara byte a byte o bundle versionado com uma compilação nova.

## Testes integrados via HTTP

`backend/tests/test_minesweeper_acceptance.pl` sobe o servidor real em porta
livre e joga apenas pelos três endpoints públicos. Toda resposta 200/201 passa
por `check_response/2`, que confere formato, ordem das células e, em partida
ativa, ausência de `"mine"`, `"exploded"`, `"mines"`, `"seed"`, `"solution"` no
corpo bruto e de `adjacentMines` fora de células reveladas.

Para vencer sem adivinhar, o teste lê as minas da sessão em memória
(`oracle_mines/2`). O oráculo serve só ao teste: ele escolhe quais células
seguras revelar, mas cada jogada passa pela API e cada número exibido é
comparado com `adjacent_mines/5`.

## Matriz de cenários

| # | Cenário | Cobertura | Situação |
| --- | --- | --- | --- |
| 1 | Criar partida nas três dificuldades com dimensões e minas corretas | `acceptance:win_flow` (×3), `http:all_difficulties` | Automatizado |
| 2 | Bandeira antes do primeiro clique não gera minas e mantém `ready` | `acceptance:win_flow`, `game:flag_before_first_reveal_preserves_ready_and_rng` | Automatizado |
| 3 | Primeiro clique seguro nas três dificuldades | `acceptance:win_flow` (×3), `game:first_click_safe_all_presets` | Automatizado |
| 4 | Números exibidos iguais às contagens reais do Prolog | `acceptance:win_flow` (todas as respostas) | Automatizado |
| 5 | Expansão de célula 0 e borda numerada, preservando bandeiras | `acceptance:win_flow`, `game:flood_fill_*` | Automatizado |
| 6 | Revelar célula aberta não muda snapshot nem revisão | `acceptance:win_flow`, `game:repeated_reveal_is_idempotent_with_unchanged_revision` | Automatizado |
| 7 | Vitória revelando todas as seguras; minas mostradas como `mine` | `acceptance:win_flow` (×3) | Automatizado |
| 8 | Célula com bandeira não pode ser revelada (409 `cell_flagged`) | `acceptance:loss_flow`, `http:conflicts` | Automatizado |
| 9 | Derrota: mina `exploded`, demais `mine`, bandeira errada `flagged` | `acceptance:loss_flow` (×3) | Automatizado |
| 10 | Após fim, ações retornam 409 `game_over` sem alterar o snapshot | `acceptance:win_flow`, `acceptance:loss_flow` | Automatizado |
| 11 | Reiniciar: nova partida da mesma dificuldade; anterior intacta | `acceptance:win_flow`, `acceptance:loss_flow` | Automatizado |
| 12 | Falha de rede após ação: GET recupera o estado confirmado | `acceptance:network_failure_recovery` | Automatizado (servidor) |
| 13 | `toggle_flag` repetido às cegas desfaz a jogada (não é idempotente) | `acceptance:network_failure_recovery` | Automatizado (servidor) |
| 14 | Sessão expirada no meio da partida: 404 em GET e ação; novo jogo funciona | `acceptance:expired_session_mid_game`, `sessions:expiration_boundary_and_renewal` | Automatizado |
| 15 | Resposta antiga após novo jogo não afeta a partida nova | `acceptance:stale_game_isolated_after_new_game` | Servidor automatizado; descarte no cliente pendente da frente 04 |
| 16 | Nenhuma mina, semente ou número oculto no JSON de partida ativa | `acceptance` (todas as respostas), `http:create_get_and_action` | Automatizado |
| 17 | Ações concorrentes na mesma partida são serializadas | `http:concurrent_actions`, `sessions:concurrent_toggles_are_serialized` | Automatizado |
| 18 | Bundle servido corresponde ao fonte Elm | `make check-bundle` (CI) | Automatizado |
| 19 | Cliente Elm: uma ação pendente por vez, timeout → GET, ignorar partida antiga | Testes Elm da frente 04 | Pendente (frente 04) |
| 20 | Navegador: mouse, teclado, toque, grade difícil em viewport móvel | Procedimento abaixo | Pendente (frentes 04 e 05) |

Prefixos: `acceptance` = `test_minesweeper_acceptance.pl`, `game` =
`test_minesweeper_game.pl`, `http` = `test_minesweeper_http.pl`, `sessions` =
`test_minesweeper_sessions.pl`.

## Resultados registrados

23/11/2026, branch `issue-6-integracao` sobre o PR #10, SWI-Prolog 10.0.2:

| Suíte | Resultado |
| --- | --- |
| `test_minesweeper_acceptance.pl` | 5 testes (+4 subtestes) passaram; estável em 3 execuções seguidas |
| `test_minesweeper_board.pl` | 24 (+51) passaram |
| `test_minesweeper_game.pl` | 16 (+7) passaram |
| `test_minesweeper_http.pl` | 11 (+2) passaram |
| `test_minesweeper_sessions.pl` | 9 (+2) passaram |
| `test_sudoku.pl` (legado) | 27 (+19) passaram |
| `make check-bundle` | Passa depois de recompilar; o `elm.js` versionado antes desta entrega **não** correspondia ao fonte |
| `make deps && make check-bundle && make test-elm` em cópia limpa, cache Elm vazio | Passou |

## Procedimento de aceite no navegador

Executar quando as frentes 04 e 05 estiverem integradas, com `make run` e o
navegador em `http://localhost:8080`. Registrar data, navegador, versão e
resultado de cada item nesta seção.

1. **Fluxo completo com mouse**, em cada dificuldade: criar, marcar bandeira,
   revelar, observar expansão, vencer ou perder, reiniciar. Conferir contador de
   bandeiras, cronômetro (inicia na primeira revelação confirmada e para no fim)
   e que bandeiras erradas aparecem distintas na derrota.
2. **Teclado**: jogar uma partida fácil inteira sem mouse; foco sempre visível,
   ordem de tabulação previsível, revelar e marcar por tecla.
3. **Toque**: em dispositivo ou emulação móvel, usar o modo explícito de
   bandeira; nenhum toque longo obrigatório.
4. **Grade difícil em viewport móvel** (ex.: 360×740): grade 16×30 com rolagem
   utilizável, células sem encolher a ponto de inviabilizar toque.
5. **Estados sem depender só de cor**: oculta, bandeira, revelada com número,
   mina e mina detonada distinguíveis em escala de cinza.
6. **Falha de rede**: com DevTools em offline, fazer uma ação; a interface
   mostra erro, não repete `toggle_flag` sozinha e, ao voltar a rede, recupera o
   estado via GET.
7. **Sessão perdida**: reiniciar o servidor durante a partida; a próxima ação
   mostra mensagem de partida não encontrada e oferece novo jogo.
8. **Resposta atrasada**: com throttling lento, fazer uma ação e clicar em novo
   jogo antes da resposta; a resposta antiga não altera o tabuleiro novo.
9. **Sem vazamento no navegador**: na aba Network, nenhuma resposta de partida
   ativa contém `mine`, `exploded` ou `adjacentMines` em célula oculta.
10. **Página de Campo Minado**: título, favicon e textos sem referências ao
    Sudoku.

## Pendências para fechar a issue #6

- Aceite final depende das frentes 04 (cliente Elm) e 05 (grade e interface).
- Executar o procedimento de navegador e registrar os resultados acima.
- Depois do fluxo novo passar: retirar `backend/sudoku`, `test_sudoku.pl`,
  `Variant.elm`, `Local.elm`, `Overlay.elm` e o exemplo Janus do produto
  ativo; recompilar o bundle e conferir `make check-bundle`.
- Confirmar com a disciplina se CLP(FD), meta-interpretador ou Python são
  exigidos antes de prometê-los: o Campo Minado atual não usa nenhum deles.
