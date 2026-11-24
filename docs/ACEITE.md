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
| elm-format | 0.8.7 | `frontend/package.json` e `package-lock.json` |
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
make check-format
make build
```

Sem `make`:

```sh
for t in backend/tests/test_*.pl; do swipl -g run_tests -t halt "$t" || exit 1; done
cd frontend
npm ci
npx elm-format src/ tests/ --validate
npx elm make src/Main.elm --optimize --output=public/elm.js
npx elm-test
```

Sem SWI-Prolog instalado, a imagem oficial reproduz o ambiente do CI:

```sh
docker run --rm -v "$PWD":/w -w /w swipl:10.0.2 \
  sh -c 'for t in backend/tests/test_*.pl; do swipl -g run_tests -t halt "$t" || exit 1; done'
```

O artefato `frontend/public/elm.js` não é versionado no Git: `make build` (e
`make run`) gera o bundle determinístico a partir dos módulos Elm.

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
| 15 | Resposta antiga após novo jogo não afeta a partida nova | `acceptance:stale_game_isolated_after_new_game`, `elm:Descarte de respostas atrasadas` | Automatizado (servidor e cliente) |
| 16 | Nenhuma mina, semente ou número oculto no JSON de partida ativa | `acceptance` (todas as respostas), `http:create_get_and_action` | Automatizado |
| 17 | Ações concorrentes na mesma partida são serializadas | `http:concurrent_actions`, `sessions:concurrent_toggles_are_serialized` | Automatizado |
| 18 | Código Elm formatado (`elm-format`) e bundle compilável sem erros | `make check-format` e `make build` (CI) | Automatizado |
| 19 | Cliente Elm: uma ação pendente por vez, timeout → GET, ignorar partida antiga, sessão perdida | `elm:Concorrência e recuperação após resultado incerto`, `elm:Sessão perdida e reinício` | Automatizado |
| 20 | Navegador: mouse, teclado, toque, grade difícil em viewport móvel | Lógica em `elm:BoardTest` (foco, atalhos, modo bandeira, rótulos); uso real pelo procedimento abaixo | Manual: passou em 23/11/2026 |

Prefixos: `acceptance` = `test_minesweeper_acceptance.pl`, `game` =
`test_minesweeper_game.pl`, `http` = `test_minesweeper_http.pl`, `sessions` =
`test_minesweeper_sessions.pl`, `elm` = `frontend/tests/*.elm`
(`describe` correspondente).

## Resultados registrados

23/11/2026, branch `issue-6-integracao` com `main` após os PRs #12 (frente 04)
e #14 (frente 05), Sudoku retirado, SWI-Prolog 10.0.2 (Docker) e Elm 0.19.1:

| Suíte | Resultado |
| --- | --- |
| `test_minesweeper_acceptance.pl` | 5 testes (+4 subtestes) passaram |
| `test_minesweeper_board.pl` | 24 (+51) passaram |
| `test_minesweeper_game.pl` | 16 (+7) passaram |
| `test_minesweeper_http.pl` | 11 (+2) passaram |
| `test_minesweeper_sessions.pl` | 9 (+2) passaram |
| `elm-test` (`MinesweeperTest.elm`, `BoardTest.elm`) | 46 passaram |
| `swipl backend/server.pl` | Carrega sem avisos |
| `make check-format` e `make build` | `elm-format` validado e `elm.js` compilado sem erros |
| Servidor real (`docker … swipl backend/server.pl 8080`) | `/` serve "Campo Minado — Prolog + Elm", `/elm.js` 200, partida difícil criada e primeiro clique seguro via API |

## Procedimento de aceite no navegador

Com `make run` e o navegador em `http://localhost:8080`. Registrar data,
navegador, versão e resultado de cada item na tabela ao fim desta seção.

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

### Registro do aceite no navegador

Data: 23/11/2026 · Navegador: Google Chrome 157.0.8103.79 · Dispositivo: monitor de 17"; itens 3 e 4 via emulação móvel do DevTools (360×740) · Servidor: `swipl:10.0.2` em Docker (WSL)

| Item | Resultado | Observação |
| --- | --- | --- |
| 1. Mouse (fácil, médio, difícil) | Passou | |
| 2. Teclado | Passou | |
| 3. Toque / modo bandeira | Passou | |
| 4. Grade difícil em 360×740 | Passou | |
| 5. Estados sem depender de cor | Passou | |
| 6. Falha de rede | Passou | |
| 7. Sessão perdida | Passou | |
| 8. Resposta atrasada | Passou | |
| 9. Sem vazamento no Network | Passou | |

## Módulos retirados

Com o fluxo novo passando, saíram do produto ativo (continuam no histórico Git):
`backend/sudoku/`, `backend/tests/test_sudoku.pl`, `backend/python/exemplo_janus.py`,
`frontend/src/Variant.elm`, `Local.elm` e `Overlay.elm`. Nenhum deles era
importado pelo `Main.elm` nem pelo `server.pl`; o bundle não mudou.

CLP(FD), meta-interpretador e Python não são exigidos: o `AVALIACAO.md` da
disciplina cita CLP(FD) só como exemplo de uso idiomático e trata Python como
integração opcional.

## Pendências para fechar a issue #6

- CI verde e aprovação do PR #13 por @guxvr (frente 01).
