module Board exposing
    ( Config
    , HudConfig
    , InputMode(..)
    , VisualKind(..)
    , adjacentDifficulty
    , boardDensityClass
    , cellAriaLabel
    , cellDomId
    , cellVisualKind
    , clampCoord
    , difficultyDomId
    , formatElapsed
    , modeDomId
    , moveFocus
    , moveFocusColumnEdge
    , moveFocusRowEdge
    , recoveryDomId
    , restartDomId
    , revealedSafeCount
    , safeTotal
    , shortcutsDomId
    , statusSummary
    , view
    , viewDifficultyBar
    , viewHud
    , viewShortcutsPanel
    , visualKind
    )

{-| Apresentação acessível e responsiva do tabuleiro e controles do Campo Minado
(Frente 05 — Issue #5).

Consome exclusivamente os tipos públicos de `Game` e delega eventos por meio dos
registros `Config msg` e `HudConfig msg`, mantendo desacoplamento claro entre
estado de comunicação (`Main`/`Api`) e camada de apresentação (`Board`).

Navegação completa por teclado:
- Link de salto ("Ir para o tabuleiro") e atalho global `G` levam o foco direto
  para a célula ativa da grade.
- Grade semântica WAI-ARIA (`role="grid"`, `role="row"`, `role="gridcell"`) com
  roving tabindex (1 único ponto de Tab para entrar/sair do tabuleiro).
- Dentro da grade: Setas/WASD movem célula a célula, Home/End vão às pontas da
  linha, PageUp/PageDown vão às pontas da coluna, Enter/Espaço aplicam o modo
  ativo, `R` revela, `F` marca bandeira, `M` alterna modo e `Esc` devolve o foco
  aos controles do HUD.
- Fora da grade: `Tab`/`Shift+Tab`, setas esquerda/direita no seletor de
  dificuldade e no seletor de modo, atalhos `1`/`2`/`3` (dificuldade), `N`
  (nova partida), `M` (modo), `G` (ir ao tabuleiro), `U` (ressincronizar) e `?`
  (abrir/fechar painel de atalhos).
-}

import Game exposing (Cell, CellState(..), Coord, Difficulty(..), Snapshot, Status(..))
import Html exposing (..)
import Html.Attributes exposing (attribute, class, classList, id, tabindex, title, type_)
import Html.Events exposing (custom, onClick, onFocus, preventDefaultOn)
import Json.Decode as Decode
import Set exposing (Set)
import Svg exposing (svg)
import Svg.Attributes as SA


{-| Modo explícito de interação primária (clique esquerdo, toque, Enter/Espaço).
Substitui booleano solto por tipo algébrico explícito.
-}
type InputMode
    = RevealMode
    | FlagMode


{-| Representação visual derivada do estado da partida e da célula.
Torna explícitos `VisualCorrectFlag` (bandeira acertada em mina ao perder) e
`VisualWrongFlag` (bandeira em célula segura ao perder).
-}
type VisualKind
    = VisualHidden
    | VisualFlagged
    | VisualCorrectFlag
    | VisualWrongFlag
    | VisualRevealed Int
    | VisualMine
    | VisualExploded


type alias Config msg =
    { snapshot : Snapshot
    , flaggedBeforeEnd : Set ( Int, Int )
    , focused : Coord
    , inputMode : InputMode
    , isBusy : Bool
    , onPrimaryClick : Coord -> msg
    , onSecondaryClick : Coord -> msg
    , onReveal : Coord -> msg
    , onToggleFlag : Coord -> msg
    , onMoveFocus : Int -> Int -> msg
    , onFocusRowEdge : Bool -> msg
    , onFocusColumnEdge : Bool -> msg
    , onFocusCell : Coord -> msg
    , onExitGrid : msg
    , onToggleInputMode : msg
    , onNewGame : msg
    }


type alias HudConfig msg =
    { status : Maybe Status
    , elapsedSeconds : Int
    , remainingMines : Maybe Int
    , revealedCount : Maybe Int
    , safeTotal : Maybe Int
    , inputMode : InputMode
    , isSyncing : Bool
    , showShortcuts : Bool
    , onRestart : msg
    , onSetInputMode : InputMode -> msg
    , onFocusMode : InputMode -> msg
    , onToggleShortcuts : msg
    }



-- IDS DOM DETERMINÍSTICOS PARA GERENCIAMENTO DE FOCO


cellDomId : Coord -> String
cellDomId { row, col } =
    "ms-cell-" ++ String.fromInt row ++ "-" ++ String.fromInt col


difficultyDomId : Difficulty -> String
difficultyDomId difficulty =
    "ms-diff-" ++ Game.difficultyToString difficulty


modeDomId : InputMode -> String
modeDomId mode =
    case mode of
        RevealMode ->
            "ms-mode-reveal"

        FlagMode ->
            "ms-mode-flag"


restartDomId : String
restartDomId =
    "ms-restart-btn"


recoveryDomId : String
recoveryDomId =
    "ms-recovery-btn"


shortcutsDomId : String
shortcutsDomId =
    "ms-shortcuts-btn"



-- HELPERS PUROS E TESTÁVEIS


clampCoord : Snapshot -> Coord -> Coord
clampCoord snapshot coord =
    { row = clamp 0 (max 0 (snapshot.rows - 1)) coord.row
    , col = clamp 0 (max 0 (snapshot.cols - 1)) coord.col
    }


moveFocus : Snapshot -> Int -> Int -> Coord -> Coord
moveFocus snapshot dRow dCol current =
    clampCoord snapshot
        { row = current.row + dRow
        , col = current.col + dCol
        }


moveFocusRowEdge : Snapshot -> Bool -> Coord -> Coord
moveFocusRowEdge snapshot toEnd current =
    let
        targetCol =
            if toEnd then
                max 0 (snapshot.cols - 1)

            else
                0
    in
    clampCoord snapshot { row = current.row, col = targetCol }


moveFocusColumnEdge : Snapshot -> Bool -> Coord -> Coord
moveFocusColumnEdge snapshot toBottom current =
    let
        targetRow =
            if toBottom then
                max 0 (snapshot.rows - 1)

            else
                0
    in
    clampCoord snapshot { row = targetRow, col = current.col }


adjacentDifficulty : Int -> Difficulty -> Difficulty
adjacentDifficulty delta current =
    case ( current, delta < 0 ) of
        ( Easy, True ) ->
            Hard

        ( Easy, False ) ->
            Medium

        ( Medium, True ) ->
            Easy

        ( Medium, False ) ->
            Hard

        ( Hard, True ) ->
            Medium

        ( Hard, False ) ->
            Easy


formatElapsed : Int -> String
formatElapsed totalSeconds =
    let
        safeSeconds =
            max 0 totalSeconds

        mins =
            safeSeconds // 60

        secs =
            modBy 60 safeSeconds

        pad n =
            if n < 10 then
                "0" ++ String.fromInt n

            else
                String.fromInt n
    in
    pad mins ++ ":" ++ pad secs


revealedSafeCount : Snapshot -> Int
revealedSafeCount snapshot =
    snapshot.cells
        |> List.filter
            (\cell ->
                case cell.state of
                    Revealed _ ->
                        True

                    _ ->
                        False
            )
        |> List.length


safeTotal : Snapshot -> Int
safeTotal snapshot =
    max 0 (snapshot.rows * snapshot.cols - snapshot.mineCount)


visualKind : Status -> CellState -> VisualKind
visualKind status state =
    case state of
        Hidden ->
            VisualHidden

        Flagged ->
            if Game.isWrongFlag status state then
                VisualWrongFlag

            else
                VisualFlagged

        Revealed n ->
            VisualRevealed n

        Mine ->
            VisualMine

        Exploded ->
            VisualExploded


cellVisualKind : Status -> Set ( Int, Int ) -> Cell -> VisualKind
cellVisualKind status flaggedBeforeEnd cell =
    if status == Lost && cell.state == Mine && Set.member ( cell.row, cell.col ) flaggedBeforeEnd then
        VisualCorrectFlag

    else
        visualKind status cell.state


cellAriaLabel : Status -> Set ( Int, Int ) -> Cell -> String
cellAriaLabel status flaggedBeforeEnd cell =
    let
        pos =
            "Linha "
                ++ String.fromInt (cell.row + 1)
                ++ ", coluna "
                ++ String.fromInt (cell.col + 1)
                ++ ": "
    in
    case cellVisualKind status flaggedBeforeEnd cell of
        VisualHidden ->
            pos ++ "oculta"

        VisualFlagged ->
            pos ++ "marcada com bandeira"

        VisualCorrectFlag ->
            pos ++ "bandeira correta (mina acertada)"

        VisualWrongFlag ->
            pos ++ "bandeira incorreta"

        VisualRevealed 0 ->
            pos ++ "revelada, sem minas adjacentes"

        VisualRevealed 1 ->
            pos ++ "revelada, 1 mina adjacente"

        VisualRevealed n ->
            pos ++ "revelada, " ++ String.fromInt n ++ " minas adjacentes"

        VisualMine ->
            pos ++ "mina"

        VisualExploded ->
            pos ++ "mina detonada"


statusSummary : Status -> { title : String, description : String, badge : String }
statusSummary status =
    case status of
        Ready ->
            { title = "Pronto para começar"
            , description = "O primeiro clique revelado é sempre seguro. Você já pode marcar bandeiras se desejar."
            , badge = "Pronto"
            }

        Playing ->
            { title = "Partida em andamento"
            , description = "Revele todas as células sem mina para vencer."
            , badge = "Jogando"
            }

        Won ->
            { title = "Vitória!"
            , description = "Você revelou todas as células seguras do campo minado."
            , badge = "Vitória"
            }

        Lost ->
            { title = "Derrota — você detonou uma mina"
            , description = "As minas, bandeiras corretas (verdes) e eventuais bandeiras incorretas foram reveladas no tabuleiro."
            , badge = "Derrota"
            }


boardDensityClass : Int -> String
boardDensityClass cols =
    if cols >= 25 then
        "board--hard"

    else if cols >= 14 then
        "board--medium"

    else
        "board--easy"


difficultyMeta : Difficulty -> { name : String, shortcut : String }
difficultyMeta difficulty =
    case difficulty of
        Easy ->
            { name = "Fácil", shortcut = "1" }

        Medium ->
            { name = "Médio", shortcut = "2" }

        Hard ->
            { name = "Difícil", shortcut = "3" }



-- VIEW: SELETOR DE DIFICULDADE, HUD E PAINEL DE ATALHOS


viewDifficultyBar :
    { current : Difficulty
    , onSelect : Difficulty -> msg
    , onFocusDifficulty : Difficulty -> msg
    }
    -> Html msg
viewDifficultyBar cfg =
    nav [ class "difficulty-bar", attribute "aria-label" "Seleção de dificuldade" ]
        (List.map (viewDifficultyButton cfg) Game.allDifficulties)


viewDifficultyButton :
    { current : Difficulty
    , onSelect : Difficulty -> msg
    , onFocusDifficulty : Difficulty -> msg
    }
    -> Difficulty
    -> Html msg
viewDifficultyButton cfg difficulty =
    let
        dims =
            Game.dimensions difficulty

        meta =
            difficultyMeta difficulty

        isActive =
            cfg.current == difficulty

        onKeyNav =
            custom "keydown"
                (Decode.field "key" Decode.string
                    |> Decode.andThen
                        (\key ->
                            case key of
                                "ArrowLeft" ->
                                    Decode.succeed
                                        { message = cfg.onFocusDifficulty (adjacentDifficulty -1 difficulty)
                                        , stopPropagation = True
                                        , preventDefault = True
                                        }

                                "ArrowRight" ->
                                    Decode.succeed
                                        { message = cfg.onFocusDifficulty (adjacentDifficulty 1 difficulty)
                                        , stopPropagation = True
                                        , preventDefault = True
                                        }

                                _ ->
                                    Decode.fail "ignorar"
                        )
                )
    in
    button
        [ type_ "button"
        , id (difficultyDomId difficulty)
        , classList
            [ ( "diff-btn", True )
            , ( "is-active", isActive )
            ]
        , attribute "aria-pressed" (boolAttr isActive)
        , attribute "aria-keyshortcuts" meta.shortcut
        , onClick (cfg.onSelect difficulty)
        , onKeyNav
        ]
        [ span [ class "diff-head" ]
            [ span [ class "diff-name" ] [ text meta.name ]
            , node "kbd" [ class "kbd-hint", attribute "aria-hidden" "true" ] [ text meta.shortcut ]
            ]
        , span [ class "diff-meta" ]
            [ text
                (String.fromInt dims.rows
                    ++ "×"
                    ++ String.fromInt dims.cols
                    ++ " · "
                    ++ String.fromInt dims.mineCount
                    ++ " minas"
                )
            ]
        ]


viewHud : HudConfig msg -> Html msg
viewHud cfg =
    let
        remainingText =
            cfg.remainingMines
                |> Maybe.map String.fromInt
                |> Maybe.withDefault "--"

        isOverFlagged =
            cfg.remainingMines
                |> Maybe.map (\n -> n < 0)
                |> Maybe.withDefault False

        safeProgressText =
            case ( cfg.revealedCount, cfg.safeTotal ) of
                ( Just done, Just total ) ->
                    String.fromInt done ++ "/" ++ String.fromInt total

                _ ->
                    "--"

        statusBadge =
            if cfg.isSyncing then
                "Sincronizando..."

            else
                cfg.status
                    |> Maybe.map (statusSummary >> .badge)
                    |> Maybe.withDefault "Carregando"

        modeArrowKey targetMode =
            custom "keydown"
                (Decode.field "key" Decode.string
                    |> Decode.andThen
                        (\key ->
                            if key == "ArrowLeft" || key == "ArrowRight" then
                                Decode.succeed
                                    { message = cfg.onFocusMode targetMode
                                    , stopPropagation = True
                                    , preventDefault = True
                                    }

                            else
                                Decode.fail "ignorar"
                        )
                )
    in
    section [ class "hud-panel", attribute "aria-label" "Painel da partida" ]
        [ div [ class "hud-metrics" ]
            [ metricCard "Bandeiras"
                remainingText
                (if isOverFlagged then
                    "metric-value--warn"

                 else
                    ""
                )
            , metricCard "Tempo" (formatElapsed cfg.elapsedSeconds) ""
            , metricCard "Seguras" safeProgressText ""
            , div
                [ classList
                    [ ( "metric-card", True )
                    , ( "metric-card--won", cfg.status == Just Won )
                    , ( "metric-card--lost", cfg.status == Just Lost )
                    ]
                , attribute "role" "status"
                , attribute "aria-live" "polite"
                ]
                [ span [ class "metric-label" ] [ text "Estado" ]
                , strong [ class "metric-value" ] [ text statusBadge ]
                ]
            ]
        , div [ class "hud-actions" ]
            [ div
                [ class "mode-switch"
                , attribute "role" "group"
                , attribute "aria-label" "Modo de toque e clique principal (atalho M)"
                ]
                [ button
                    [ type_ "button"
                    , id (modeDomId RevealMode)
                    , classList [ ( "mode-btn", True ), ( "is-active", cfg.inputMode == RevealMode ) ]
                    , attribute "aria-pressed" (boolAttr (cfg.inputMode == RevealMode))
                    , attribute "aria-keyshortcuts" "m"
                    , onClick (cfg.onSetInputMode RevealMode)
                    , modeArrowKey FlagMode
                    ]
                    [ iconReveal
                    , span [] [ text "Revelar" ]
                    ]
                , button
                    [ type_ "button"
                    , id (modeDomId FlagMode)
                    , classList [ ( "mode-btn", True ), ( "is-active", cfg.inputMode == FlagMode ) ]
                    , attribute "aria-pressed" (boolAttr (cfg.inputMode == FlagMode))
                    , attribute "aria-keyshortcuts" "m"
                    , onClick (cfg.onSetInputMode FlagMode)
                    , modeArrowKey RevealMode
                    ]
                    [ iconFlag
                    , span [] [ text "Bandeira" ]
                    ]
                ]
            , button
                [ type_ "button"
                , id restartDomId
                , class "btn btn--primary restart-btn"
                , attribute "aria-keyshortcuts" "n"
                , onClick cfg.onRestart
                ]
                [ span [] [ text "Reiniciar" ]
                , node "kbd" [ class "kbd-hint kbd-hint--on-accent", attribute "aria-hidden" "true" ] [ text "N" ]
                ]
            , button
                [ type_ "button"
                , id shortcutsDomId
                , classList [ ( "btn btn--ghost shortcuts-btn", True ), ( "is-active", cfg.showShortcuts ) ]
                , attribute "aria-expanded" (boolAttr cfg.showShortcuts)
                , attribute "aria-controls" "ms-shortcuts-panel"
                , attribute "aria-keyshortcuts" "?"
                , onClick cfg.onToggleShortcuts
                ]
                [ span [] [ text "Teclado" ]
                , node "kbd" [ class "kbd-hint", attribute "aria-hidden" "true" ] [ text "?" ]
                ]
            ]
        ]


viewShortcutsPanel : Bool -> msg -> Html msg
viewShortcutsPanel isOpen onClose =
    if not isOpen then
        text ""

    else
        section
            [ id "ms-shortcuts-panel"
            , class "shortcuts-panel"
            , attribute "aria-label" "Guia de navegação por teclado"
            ]
            [ div [ class "shortcuts-header" ]
                [ strong [] [ text "Navegação completa por teclado" ]
                , button
                    [ type_ "button"
                    , class "btn btn--ghost btn--compact"
                    , onClick onClose
                    ]
                    [ text "Fechar (Esc)" ]
                ]
            , div [ class "shortcuts-grid" ]
                [ shortcutItem [ "Setas", "WASD" ] "Mover entre células"
                , shortcutItem [ "Home", "End" ] "Início / fim da linha"
                , shortcutItem [ "PgUp", "PgDn" ] "Topo / base da coluna"
                , shortcutItem [ "Enter", "Espaço" ] "Aplicar ação do modo ativo"
                , shortcutItem [ "R" ] "Revelar célula focada"
                , shortcutItem [ "F" ] "Alternar bandeira na célula"
                , shortcutItem [ "M" ] "Alternar modo Revelar / Bandeira"
                , shortcutItem [ "1", "2", "3" ] "Fácil / Médio / Difícil"
                , shortcutItem [ "N" ] "Reiniciar / nova partida"
                , shortcutItem [ "G" ] "Ir direto para o tabuleiro"
                , shortcutItem [ "Esc" ] "Sair da grade para controles"
                , shortcutItem [ "Tab" ] "Navegar por todos os controles"
                ]
            ]


shortcutItem : List String -> String -> Html msg
shortcutItem keys description =
    div [ class "shortcut-item" ]
        [ span [ class "shortcut-keys" ]
            (List.map (\k -> node "kbd" [ class "kbd-chip" ] [ text k ]) keys)
        , span [ class "shortcut-desc" ] [ text description ]
        ]


metricCard : String -> String -> String -> Html msg
metricCard labelText valueText extraClass =
    div [ class "metric-card" ]
        [ span [ class "metric-label" ] [ text labelText ]
        , strong [ class ("metric-value " ++ extraClass) ] [ text valueText ]
        ]



-- VIEW: TABULEIRO


view : Config msg -> Html msg
view cfg =
    let
        snapshot =
            cfg.snapshot

        rows =
            Game.cellsByRow snapshot

        ended =
            Game.isFinished snapshot.status

        clampedFocus =
            clampCoord snapshot cfg.focused
    in
    div [ class "board-container" ]
        [ viewOutcomeBanner cfg
        , if snapshot.cols >= 25 then
            p [ class "scroll-hint" ]
                [ text "Dica em telas menores: deslize o tabuleiro horizontalmente ou use as setas do teclado para percorrer todas as colunas." ]

          else
            text ""
        , div
            [ class "board-scroll"
            , attribute "aria-label" "Área do tabuleiro com rolagem"
            ]
            [ div
                [ id "ms-board-grid"
                , class ("board " ++ boardDensityClass snapshot.cols)
                , classList
                    [ ( "board--busy", cfg.isBusy && not ended )
                    , ( "board--won", snapshot.status == Won )
                    , ( "board--lost", snapshot.status == Lost )
                    ]
                , attribute "role" "grid"
                , attribute "aria-label"
                    ("Tabuleiro de Campo Minado "
                        ++ String.fromInt snapshot.rows
                        ++ " por "
                        ++ String.fromInt snapshot.cols
                    )
                , attribute "aria-rowcount" (String.fromInt snapshot.rows)
                , attribute "aria-colcount" (String.fromInt snapshot.cols)
                , attribute "aria-busy" (boolAttr (cfg.isBusy && not ended))
                , preventDefaultOn "contextmenu" (Decode.succeed ( cfg.onFocusCell clampedFocus, True ))
                ]
                (List.indexedMap (viewRow cfg clampedFocus) rows)
            ]
        , viewLegend cfg.inputMode
        ]


viewOutcomeBanner : Config msg -> Html msg
viewOutcomeBanner cfg =
    case cfg.snapshot.status of
        Won ->
            let
                info =
                    statusSummary Won
            in
            div [ class "outcome outcome--won", attribute "role" "status", attribute "aria-live" "polite" ]
                [ div [ class "outcome-copy" ]
                    [ strong [] [ text info.title ]
                    , span [] [ text info.description ]
                    ]
                , button
                    [ type_ "button"
                    , class "btn btn--primary"
                    , attribute "aria-keyshortcuts" "n"
                    , onClick cfg.onNewGame
                    ]
                    [ span [] [ text "Jogar novamente" ]
                    , node "kbd" [ class "kbd-hint kbd-hint--on-accent", attribute "aria-hidden" "true" ] [ text "N" ]
                    ]
                ]

        Lost ->
            let
                info =
                    statusSummary Lost
            in
            div [ class "outcome outcome--lost", attribute "role" "status", attribute "aria-live" "polite" ]
                [ div [ class "outcome-copy" ]
                    [ strong [] [ text info.title ]
                    , span [] [ text info.description ]
                    ]
                , button
                    [ type_ "button"
                    , class "btn btn--primary"
                    , attribute "aria-keyshortcuts" "n"
                    , onClick cfg.onNewGame
                    ]
                    [ span [] [ text "Nova partida" ]
                    , node "kbd" [ class "kbd-hint kbd-hint--on-accent", attribute "aria-hidden" "true" ] [ text "N" ]
                    ]
                ]

        _ ->
            text ""


viewRow : Config msg -> Coord -> Int -> List Cell -> Html msg
viewRow cfg focusedCoord rowIdx rowCells =
    div
        [ class "board-row"
        , attribute "role" "row"
        , attribute "aria-rowindex" (String.fromInt (rowIdx + 1))
        ]
        (List.map (viewCell cfg focusedCoord) rowCells)


viewCell : Config msg -> Coord -> Cell -> Html msg
viewCell cfg focusedCoord cell =
    let
        coord =
            { row = cell.row, col = cell.col }

        kind =
            cellVisualKind cfg.snapshot.status cfg.flaggedBeforeEnd cell

        isFocused =
            focusedCoord == coord

        ended =
            Game.isFinished cfg.snapshot.status

        isActionDisabled =
            cfg.isBusy || ended

        labelText =
            cellAriaLabel cfg.snapshot.status cfg.flaggedBeforeEnd cell
    in
    button
        [ type_ "button"
        , id (cellDomId coord)
        , class (cellClasses kind)
        , classList [ ( "cell--focused", isFocused ) ]
        , tabindex
            (if isFocused then
                0

             else
                -1
            )
        , attribute "role" "gridcell"
        , attribute "aria-rowindex" (String.fromInt (cell.row + 1))
        , attribute "aria-colindex" (String.fromInt (cell.col + 1))
        , attribute "aria-label" labelText
        , attribute "aria-disabled" (boolAttr isActionDisabled)
        , title labelText
        , onFocus (cfg.onFocusCell coord)
        , onClick (cfg.onPrimaryClick coord)
        , preventDefaultOn "contextmenu" (Decode.succeed ( cfg.onSecondaryClick coord, True ))
        , custom "keydown" (cellKeyDecoder cfg coord)
        ]
        [ viewCellContent kind ]


cellClasses : VisualKind -> String
cellClasses kind =
    case kind of
        VisualHidden ->
            "ms-cell cell--hidden"

        VisualFlagged ->
            "ms-cell cell--flagged"

        VisualCorrectFlag ->
            "ms-cell cell--correct-flag"

        VisualWrongFlag ->
            "ms-cell cell--wrong-flag"

        VisualRevealed 0 ->
            "ms-cell cell--revealed cell--empty"

        VisualRevealed n ->
            "ms-cell cell--revealed cell--num-" ++ String.fromInt n

        VisualMine ->
            "ms-cell cell--mine"

        VisualExploded ->
            "ms-cell cell--exploded"


viewCellContent : VisualKind -> Html msg
viewCellContent kind =
    case kind of
        VisualHidden ->
            span [ class "cell-sr-only" ] [ text "Oculta" ]

        VisualFlagged ->
            iconFlag

        VisualCorrectFlag ->
            iconCorrectFlag

        VisualWrongFlag ->
            iconWrongFlag

        VisualRevealed 0 ->
            text ""

        VisualRevealed n ->
            span [ class "cell-number" ] [ text (String.fromInt n) ]

        VisualMine ->
            iconMine

        VisualExploded ->
            iconExploded


cellKeyDecoder :
    Config msg
    -> Coord
    -> Decode.Decoder { message : msg, stopPropagation : Bool, preventDefault : Bool }
cellKeyDecoder cfg coord =
    let
        handle message =
            Decode.succeed
                { message = message
                , stopPropagation = True
                , preventDefault = True
                }
    in
    Decode.map4
        (\key ctrl alt meta -> ( key, ctrl || alt || meta ))
        (Decode.field "key" Decode.string)
        (Decode.field "ctrlKey" Decode.bool)
        (Decode.field "altKey" Decode.bool)
        (Decode.field "metaKey" Decode.bool)
        |> Decode.andThen
            (\( key, hasModifier ) ->
                if hasModifier then
                    Decode.fail "modificador ativo"

                else
                    case key of
                        "ArrowUp" ->
                            handle (cfg.onMoveFocus -1 0)

                        "ArrowDown" ->
                            handle (cfg.onMoveFocus 1 0)

                        "ArrowLeft" ->
                            handle (cfg.onMoveFocus 0 -1)

                        "ArrowRight" ->
                            handle (cfg.onMoveFocus 0 1)

                        "w" ->
                            handle (cfg.onMoveFocus -1 0)

                        "W" ->
                            handle (cfg.onMoveFocus -1 0)

                        "s" ->
                            handle (cfg.onMoveFocus 1 0)

                        "S" ->
                            handle (cfg.onMoveFocus 1 0)

                        "a" ->
                            handle (cfg.onMoveFocus 0 -1)

                        "A" ->
                            handle (cfg.onMoveFocus 0 -1)

                        "d" ->
                            handle (cfg.onMoveFocus 0 1)

                        "D" ->
                            handle (cfg.onMoveFocus 0 1)

                        "Home" ->
                            handle (cfg.onFocusRowEdge False)

                        "End" ->
                            handle (cfg.onFocusRowEdge True)

                        "PageUp" ->
                            handle (cfg.onFocusColumnEdge False)

                        "PageDown" ->
                            handle (cfg.onFocusColumnEdge True)

                        "Enter" ->
                            handle (cfg.onPrimaryClick coord)

                        " " ->
                            handle (cfg.onPrimaryClick coord)

                        "r" ->
                            handle (cfg.onReveal coord)

                        "R" ->
                            handle (cfg.onReveal coord)

                        "f" ->
                            handle (cfg.onToggleFlag coord)

                        "F" ->
                            handle (cfg.onToggleFlag coord)

                        "m" ->
                            handle cfg.onToggleInputMode

                        "M" ->
                            handle cfg.onToggleInputMode

                        "Escape" ->
                            handle cfg.onExitGrid

                        _ ->
                            Decode.fail "tecla não tratada pela célula"
            )


viewLegend : InputMode -> Html msg
viewLegend inputMode =
    let
        activeModeLabel =
            case inputMode of
                RevealMode ->
                    "Revelar"

                FlagMode ->
                    "Bandeira"
    in
    div [ class "board-legend", attribute "aria-label" "Legenda de símbolos e atalhos de teclado" ]
        [ span [ class "legend-item" ] [ iconFlag, text " Bandeira (botão direito ou F)" ]
        , span [ class "legend-item" ] [ iconMine, text " Mina" ]
        , span [ class "legend-item" ] [ iconCorrectFlag, text " Bandeira correta na derrota" ]
        , span [ class "legend-item" ] [ iconWrongFlag, text " Bandeira incorreta na derrota" ]
        , span [ class "legend-item" ]
            [ text
                ("Teclado: Setas/WASD/Home/End/PgUp/PgDn · Enter/Espaço ("
                    ++ activeModeLabel
                    ++ ") · R revela · F bandeira · M modo · 1/2/3 dificuldade · N novo jogo · G grade · Esc controles · ? ajuda"
                )
            ]
        ]



-- ÍCONES SVG (INDEPENDENTES DE COR)


iconReveal : Html msg
iconReveal =
    svg
        [ SA.viewBox "0 0 24 24"
        , SA.class "icon icon-reveal"
        , attribute "aria-hidden" "true"
        ]
        [ Svg.circle
            [ SA.cx "11"
            , SA.cy "11"
            , SA.r "6"
            , SA.fill "none"
            , SA.stroke "currentColor"
            , SA.strokeWidth "2"
            ]
            []
        , Svg.line
            [ SA.x1 "15.5"
            , SA.y1 "15.5"
            , SA.x2 "20"
            , SA.y2 "20"
            , SA.stroke "currentColor"
            , SA.strokeWidth "2"
            , SA.strokeLinecap "round"
            ]
            []
        ]


iconFlag : Html msg
iconFlag =
    svg
        [ SA.viewBox "0 0 24 24"
        , SA.class "icon icon-flag"
        , attribute "aria-hidden" "true"
        ]
        [ Svg.line
            [ SA.x1 "7"
            , SA.y1 "4"
            , SA.x2 "7"
            , SA.y2 "20"
            , SA.stroke "currentColor"
            , SA.strokeWidth "2.2"
            , SA.strokeLinecap "round"
            ]
            []
        , Svg.polygon [ SA.points "7,4 19,8.5 7,13", SA.fill "var(--flag-fill, #d9480f)" ] []
        , Svg.line
            [ SA.x1 "4.5"
            , SA.y1 "20"
            , SA.x2 "11.5"
            , SA.y2 "20"
            , SA.stroke "currentColor"
            , SA.strokeWidth "2.2"
            , SA.strokeLinecap "round"
            ]
            []
        ]


iconCorrectFlag : Html msg
iconCorrectFlag =
    svg
        [ SA.viewBox "0 0 24 24"
        , SA.class "icon icon-correct-flag"
        , attribute "aria-hidden" "true"
        ]
        [ Svg.line
            [ SA.x1 "6.5"
            , SA.y1 "4"
            , SA.x2 "6.5"
            , SA.y2 "20"
            , SA.stroke "currentColor"
            , SA.strokeWidth "2.2"
            , SA.strokeLinecap "round"
            ]
            []
        , Svg.polygon [ SA.points "6.5,4 18.5,8.5 6.5,13", SA.fill "var(--good, #2b8a3e)" ] []
        , Svg.line
            [ SA.x1 "4"
            , SA.y1 "20"
            , SA.x2 "11"
            , SA.y2 "20"
            , SA.stroke "currentColor"
            , SA.strokeWidth "2.2"
            , SA.strokeLinecap "round"
            ]
            []
        , Svg.polyline
            [ SA.points "13.5,16.5 16.2,19.2 21,13.5"
            , SA.fill "none"
            , SA.stroke "var(--good, #2b8a3e)"
            , SA.strokeWidth "2.6"
            , SA.strokeLinecap "round"
            , SA.strokeLinejoin "round"
            ]
            []
        ]


iconWrongFlag : Html msg
iconWrongFlag =
    svg
        [ SA.viewBox "0 0 24 24"
        , SA.class "icon icon-wrong-flag"
        , attribute "aria-hidden" "true"
        ]
        [ Svg.line
            [ SA.x1 "7"
            , SA.y1 "4"
            , SA.x2 "7"
            , SA.y2 "20"
            , SA.stroke "currentColor"
            , SA.strokeWidth "2"
            , SA.strokeLinecap "round"
            , SA.opacity "0.55"
            ]
            []
        , Svg.polygon
            [ SA.points "7,4 18,8.5 7,13"
            , SA.fill "var(--flag-fill, #d9480f)"
            , SA.opacity "0.55"
            ]
            []
        , Svg.line
            [ SA.x1 "4"
            , SA.y1 "4"
            , SA.x2 "20"
            , SA.y2 "20"
            , SA.stroke "var(--danger, #c92a2a)"
            , SA.strokeWidth "2.8"
            , SA.strokeLinecap "round"
            ]
            []
        , Svg.line
            [ SA.x1 "20"
            , SA.y1 "4"
            , SA.x2 "4"
            , SA.y2 "20"
            , SA.stroke "var(--danger, #c92a2a)"
            , SA.strokeWidth "2.8"
            , SA.strokeLinecap "round"
            ]
            []
        ]


iconMine : Html msg
iconMine =
    svg
        [ SA.viewBox "0 0 24 24"
        , SA.class "icon icon-mine"
        , attribute "aria-hidden" "true"
        ]
        [ Svg.circle [ SA.cx "12", SA.cy "12", SA.r "5.5", SA.fill "currentColor" ] []
        , Svg.line
            [ SA.x1 "12"
            , SA.y1 "3"
            , SA.x2 "12"
            , SA.y2 "21"
            , SA.stroke "currentColor"
            , SA.strokeWidth "2.2"
            , SA.strokeLinecap "round"
            ]
            []
        , Svg.line
            [ SA.x1 "3"
            , SA.y1 "12"
            , SA.x2 "21"
            , SA.y2 "12"
            , SA.stroke "currentColor"
            , SA.strokeWidth "2.2"
            , SA.strokeLinecap "round"
            ]
            []
        , Svg.line
            [ SA.x1 "5.6"
            , SA.y1 "5.6"
            , SA.x2 "18.4"
            , SA.y2 "18.4"
            , SA.stroke "currentColor"
            , SA.strokeWidth "2"
            , SA.strokeLinecap "round"
            ]
            []
        , Svg.line
            [ SA.x1 "18.4"
            , SA.y1 "5.6"
            , SA.x2 "5.6"
            , SA.y2 "18.4"
            , SA.stroke "currentColor"
            , SA.strokeWidth "2"
            , SA.strokeLinecap "round"
            ]
            []
        , Svg.circle [ SA.cx "10", SA.cy "10", SA.r "1.5", SA.fill "var(--panel, #fff)" ] []
        ]


iconExploded : Html msg
iconExploded =
    svg
        [ SA.viewBox "0 0 24 24"
        , SA.class "icon icon-exploded"
        , attribute "aria-hidden" "true"
        ]
        [ Svg.polygon
            [ SA.points "12,1.5 14.5,7.2 20.5,5.5 16.8,10.8 22.5,13.5 16.2,15.2 18.5,21.5 12.8,17.5 8.5,22.2 8.2,16 2,15.5 6.8,11.2 4,5.2 9.8,7.2"
            , SA.fill "var(--exploded-burst, #ffd43b)"
            , SA.stroke "currentColor"
            , SA.strokeWidth "1.4"
            ]
            []
        , Svg.circle [ SA.cx "12", SA.cy "12", SA.r "3.6", SA.fill "currentColor" ] []
        ]


boolAttr : Bool -> String
boolAttr b =
    if b then
        "true"

    else
        "false"
