module Main exposing
    ( Model
    , Msg(..)
    , PendingRequest(..)
    , ScreenState(..)
    , ViewState
    , globalKeyDecoder
    , init
    , isBusy
    , main
    , subscriptions
    , toViewState
    , update
    , view
    )

{-| Coordenação da partida de Campo Minado (Frentes 04 e 05).

Responsável pelo modelo TEA, ciclo de vida das requisições HTTP, bloqueio de
ações concorrentes, descarte de respostas de partidas antigas, recuperação via
GET após timeout/falha incerta, tratamento de sessão perdida, cronômetro local
e coordenação de foco, atalhos globais de teclado e modo de entrada com `Board`.

-}

import Api exposing (Action(..), ApiError)
import Board exposing (InputMode(..))
import Browser
import Browser.Dom as Dom
import Browser.Events
import Explosion
import Game exposing (Cell, CellState(..), Coord, Difficulty(..), Snapshot, Status(..))
import Html exposing (Html, button, div, footer, h1, h2, header, main_, p, section, span, text)
import Html.Attributes exposing (attribute, class, classList, disabled, id, type_)
import Html.Events exposing (onClick)
import Json.Decode as Decode
import Set exposing (Set)
import Task
import Time


main : Program Decode.Value Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = view
        }



-- MODELO


type ScreenState
    = Loading
    | Active Snapshot
    | Failed String
    | SessionLost String


type PendingRequest
    = Idle
    | CreatingGame
    | MutatingAction Action
    | SyncingAfterUncertainAction
    | SyncFailed


type alias Model =
    { difficulty : Difficulty
    , screen : ScreenState
    , pending : PendingRequest
    , requestToken : Int
    , elapsedSeconds : Int
    , timerRunning : Bool
    , feedback : Maybe String
    , focused : Coord
    , inputMode : InputMode
    , flaggedBeforeEnd : Set ( Int, Int )
    , showShortcuts : Bool
    , liveAnnouncement : String
    }


{-| Projeção de leitura para componentes de interface (Frente 05):
grade, seletor de dificuldade, contador de minas, cronômetro, foco, modo de
entrada e resultado.
-}
type alias ViewState =
    { difficulty : Difficulty
    , screen : ScreenState
    , pending : PendingRequest
    , isBusy : Bool
    , elapsedSeconds : Int
    , remainingMines : Maybe Int
    , feedback : Maybe String
    , focused : Coord
    , inputMode : InputMode
    , flaggedBeforeEnd : Set ( Int, Int )
    , showShortcuts : Bool
    , liveAnnouncement : String
    }


toViewState : Model -> ViewState
toViewState model =
    { difficulty = model.difficulty
    , screen = model.screen
    , pending = model.pending
    , isBusy = isBusy model
    , elapsedSeconds = model.elapsedSeconds
    , remainingMines =
        case model.screen of
            Active snapshot ->
                Just (Game.remainingMines snapshot)

            _ ->
                Nothing
    , feedback = model.feedback
    , focused = model.focused
    , inputMode = model.inputMode
    , flaggedBeforeEnd = model.flaggedBeforeEnd
    , showShortcuts = model.showShortcuts
    , liveAnnouncement = model.liveAnnouncement
    }


isBusy : Model -> Bool
isBusy model =
    model.pending /= Idle


init : Decode.Value -> ( Model, Cmd Msg )
init _ =
    startNewGame Easy
        { difficulty = Easy
        , screen = Loading
        , pending = CreatingGame
        , requestToken = 0
        , elapsedSeconds = 0
        , timerRunning = False
        , feedback = Nothing
        , focused = { row = 0, col = 0 }
        , inputMode = RevealMode
        , flaggedBeforeEnd = Set.empty
        , showShortcuts = False
        , liveAnnouncement = ""
        }



-- MENSAGENS


type Msg
    = SelectDifficulty Difficulty
    | RestartGame
    | RevealCell Coord
    | ToggleFlag Coord
    | PrimaryCellAction Coord
    | SetInputMode InputMode
    | ToggleInputMode
    | FocusCell Coord
    | MoveFocus Int Int
    | FocusRowEdge Bool
    | FocusColumnEdge Bool
    | FocusBoard
    | FocusControl String
    | FocusModeButton InputMode
    | ToggleShortcutsHelp
    | HandleEscape
    | FocusCompleted
    | SyncGame
    | Tick
    | CreateGameResponse Int (Result ApiError Snapshot)
    | ActionResponse Int String (Result ApiError Snapshot)
    | SyncResponse Int String (Result ApiError Snapshot)



-- ATUALIZAÇÃO


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SelectDifficulty difficulty ->
            startNewGame difficulty model

        RestartGame ->
            startNewGame model.difficulty model

        RevealCell coord ->
            sendPlayerAction (Api.Reveal coord) model

        ToggleFlag coord ->
            sendPlayerAction (Api.ToggleFlag coord) model

        PrimaryCellAction coord ->
            let
                action =
                    case model.inputMode of
                        RevealMode ->
                            Api.Reveal coord

                        FlagMode ->
                            Api.ToggleFlag coord

                ( nextModel, cmd ) =
                    sendPlayerAction action model
            in
            ( { nextModel | focused = coord }, cmd )

        SetInputMode mode ->
            ( { model
                | inputMode = mode
                , liveAnnouncement = modeAnnouncement mode
              }
            , Cmd.none
            )

        ToggleInputMode ->
            let
                nextMode =
                    case model.inputMode of
                        RevealMode ->
                            FlagMode

                        FlagMode ->
                            RevealMode
            in
            ( { model
                | inputMode = nextMode
                , liveAnnouncement = modeAnnouncement nextMode
              }
            , Cmd.none
            )

        FocusCell coord ->
            case model.screen of
                Active snapshot ->
                    ( { model | focused = Board.clampCoord snapshot coord }, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        MoveFocus dRow dCol ->
            case model.screen of
                Active snapshot ->
                    let
                        nextCoord =
                            Board.moveFocus snapshot dRow dCol model.focused
                    in
                    ( { model | focused = nextCoord }
                    , focusCellCmd nextCoord
                    )

                _ ->
                    ( model, Cmd.none )

        FocusRowEdge toEnd ->
            case model.screen of
                Active snapshot ->
                    let
                        nextCoord =
                            Board.moveFocusRowEdge snapshot toEnd model.focused
                    in
                    ( { model | focused = nextCoord }
                    , focusCellCmd nextCoord
                    )

                _ ->
                    ( model, Cmd.none )

        FocusColumnEdge toBottom ->
            case model.screen of
                Active snapshot ->
                    let
                        nextCoord =
                            Board.moveFocusColumnEdge snapshot toBottom model.focused
                    in
                    ( { model | focused = nextCoord }
                    , focusCellCmd nextCoord
                    )

                _ ->
                    ( model, Cmd.none )

        FocusBoard ->
            case model.screen of
                Active snapshot ->
                    let
                        target =
                            Board.clampCoord snapshot model.focused
                    in
                    ( { model
                        | focused = target
                        , showShortcuts = False
                      }
                    , focusCellCmd target
                    )

                _ ->
                    ( model, focusElementCmd Board.recoveryDomId )

        FocusControl elementId ->
            ( model, focusElementCmd elementId )

        FocusModeButton mode ->
            ( { model
                | inputMode = mode
                , liveAnnouncement = modeAnnouncement mode
              }
            , focusElementCmd (Board.modeDomId mode)
            )

        ToggleShortcutsHelp ->
            let
                nextOpen =
                    not model.showShortcuts
            in
            ( { model
                | showShortcuts = nextOpen
                , liveAnnouncement =
                    if nextOpen then
                        "Painel de atalhos de teclado aberto."

                    else
                        "Painel de atalhos de teclado fechado."
              }
            , Cmd.none
            )

        HandleEscape ->
            if model.showShortcuts then
                ( { model
                    | showShortcuts = False
                    , liveAnnouncement = "Painel de atalhos de teclado fechado."
                  }
                , focusElementCmd Board.shortcutsDomId
                )

            else
                case model.screen of
                    Active _ ->
                        ( model, focusElementCmd Board.restartDomId )

                    _ ->
                        ( model, Cmd.none )

        FocusCompleted ->
            ( model, Cmd.none )

        SyncGame ->
            if model.pending /= Idle && model.pending /= SyncFailed then
                -- Evita disparar GET concorrente enquanto outra requisição já está em andamento.
                ( model, Cmd.none )

            else
                case model.screen of
                    Active snapshot ->
                        let
                            nextToken =
                                model.requestToken + 1
                        in
                        ( { model
                            | pending = SyncingAfterUncertainAction
                            , requestToken = nextToken
                            , feedback = Just "Consultando estado confirmado da partida no servidor..."
                          }
                        , Api.fetchGame snapshot.id (SyncResponse nextToken snapshot.id)
                        )

                    _ ->
                        ( model, Cmd.none )

        Tick ->
            if model.timerRunning then
                case model.screen of
                    Active snapshot ->
                        if snapshot.status == Playing then
                            ( { model | elapsedSeconds = model.elapsedSeconds + 1 }
                            , Cmd.none
                            )

                        else
                            ( { model | timerRunning = False }, Cmd.none )

                    _ ->
                        ( { model | timerRunning = False }, Cmd.none )

            else
                ( model, Cmd.none )

        CreateGameResponse token result ->
            if token /= model.requestToken then
                -- Ignora resposta atrasada de uma tentativa anterior de novo jogo.
                ( model, Cmd.none )

            else
                case result of
                    Ok snapshot ->
                        let
                            initialFocus =
                                { row = 0, col = 0 }
                        in
                        ( { model
                            | difficulty = snapshot.difficulty
                            , screen = Active snapshot
                            , pending = Idle
                            , elapsedSeconds = 0
                            , timerRunning = snapshot.status == Playing
                            , feedback = Nothing
                            , focused = initialFocus
                            , flaggedBeforeEnd =
                                if Game.isFinished snapshot.status then
                                    Set.empty

                                else
                                    flaggedCoords snapshot
                            , liveAnnouncement =
                                "Nova partida "
                                    ++ Game.difficultyLabel snapshot.difficulty
                                    ++ " pronta. Foco na linha 1, coluna 1."
                          }
                        , focusCellCmd initialFocus
                        )

                    Err err ->
                        ( { model
                            | screen = Failed (Api.errorToMessage err)
                            , pending = Idle
                            , timerRunning = False
                            , feedback = Nothing
                          }
                        , focusElementCmd Board.recoveryDomId
                        )

        ActionResponse token gameId result ->
            if token /= model.requestToken then
                -- Ignora resposta de partida antiga após novo jogo.
                ( model, Cmd.none )

            else
                case model.screen of
                    Active current ->
                        if current.id /= gameId then
                            ( model, Cmd.none )

                        else
                            handleActionResult current result model

                    _ ->
                        ( model, Cmd.none )

        SyncResponse token gameId result ->
            if token /= model.requestToken || model.pending /= SyncingAfterUncertainAction then
                -- Ignora sincronização atrasada ou obsoleta.
                ( model, Cmd.none )

            else
                case model.screen of
                    Active current ->
                        if current.id /= gameId then
                            ( model, Cmd.none )

                        else
                            handleSyncResult current result model

                    _ ->
                        ( model, Cmd.none )


modeAnnouncement : InputMode -> String
modeAnnouncement mode =
    case mode of
        RevealMode ->
            "Modo de ação alterado para Revelar."

        FlagMode ->
            "Modo de ação alterado para Bandeira."


focusCellCmd : Coord -> Cmd Msg
focusCellCmd coord =
    focusElementCmd (Board.cellDomId coord)


focusElementCmd : String -> Cmd Msg
focusElementCmd elementId =
    Dom.focus elementId
        |> Task.attempt (\_ -> FocusCompleted)


startNewGame : Difficulty -> Model -> ( Model, Cmd Msg )
startNewGame difficulty model =
    let
        nextToken =
            model.requestToken + 1
    in
    ( { model
        | difficulty = difficulty
        , screen = Loading
        , pending = CreatingGame
        , requestToken = nextToken
        , elapsedSeconds = 0
        , timerRunning = False
        , feedback = Nothing
        , focused = { row = 0, col = 0 }
        , flaggedBeforeEnd = Set.empty
      }
    , Api.createGame difficulty (CreateGameResponse nextToken)
    )


sendPlayerAction : Action -> Model -> ( Model, Cmd Msg )
sendPlayerAction action model =
    if model.pending /= Idle then
        -- Uma ação mutante pendente por vez; bloqueia cliques concorrentes.
        ( model, Cmd.none )

    else
        case model.screen of
            Active snapshot ->
                if not (canExecuteAction snapshot action) then
                    ( model, Cmd.none )

                else
                    ( { model
                        | pending = MutatingAction action
                        , feedback = Nothing
                      }
                    , Api.sendAction snapshot.id action (ActionResponse model.requestToken snapshot.id)
                    )

            _ ->
                ( model, Cmd.none )


canExecuteAction : Snapshot -> Action -> Bool
canExecuteAction snapshot action =
    case action of
        Api.Reveal coord ->
            findCell coord snapshot
                |> Maybe.map (Game.canReveal snapshot.status)
                |> Maybe.withDefault False

        Api.ToggleFlag coord ->
            findCell coord snapshot
                |> Maybe.map (Game.canToggleFlag snapshot.status)
                |> Maybe.withDefault False


findCell : Coord -> Snapshot -> Maybe Cell
findCell coord snapshot =
    snapshot.cells
        |> List.filter (\cell -> cell.row == coord.row && cell.col == coord.col)
        |> List.head


handleActionResult : Snapshot -> Result ApiError Snapshot -> Model -> ( Model, Cmd Msg )
handleActionResult current result model =
    case result of
        Ok snapshot ->
            if snapshot.revision < current.revision then
                ( { model | pending = Idle }, Cmd.none )

            else
                ( applyConfirmedSnapshot snapshot model, Cmd.none )

        Err err ->
            if Api.isSessionLost err then
                ( { model
                    | screen = SessionLost (Api.errorToMessage err)
                    , pending = Idle
                    , timerRunning = False
                    , feedback = Nothing
                  }
                , focusElementCmd Board.recoveryDomId
                )

            else if Api.isUncertainOutcome err then
                -- Timeout/rede: não repete a ação automaticamente (especialmente toggle_flag).
                -- Consulta GET com novo token para recuperar o estado real antes de liberar comandos.
                let
                    nextToken =
                        model.requestToken + 1
                in
                ( { model
                    | pending = SyncingAfterUncertainAction
                    , requestToken = nextToken
                    , feedback =
                        Just
                            "A resposta da jogada não chegou a tempo. Sincronizando estado com o servidor..."
                  }
                , Api.fetchGame current.id (SyncResponse nextToken current.id)
                )

            else
                ( { model
                    | pending = Idle
                    , feedback = Just (Api.errorToMessage err)
                  }
                , Cmd.none
                )


handleSyncResult : Snapshot -> Result ApiError Snapshot -> Model -> ( Model, Cmd Msg )
handleSyncResult current result model =
    case result of
        Ok snapshot ->
            if snapshot.revision < current.revision then
                ( { model | pending = Idle, feedback = Nothing }, Cmd.none )

            else
                ( applyConfirmedSnapshot snapshot model, Cmd.none )

        Err err ->
            if Api.isSessionLost err then
                ( { model
                    | screen = SessionLost (Api.errorToMessage err)
                    , pending = Idle
                    , timerRunning = False
                    , feedback = Nothing
                  }
                , focusElementCmd Board.recoveryDomId
                )

            else
                -- Mantém comandos bloqueados em SyncFailed até confirmar o estado via GET ou reiniciar.
                ( { model
                    | pending = SyncFailed
                    , feedback =
                        Just
                            ("Falha ao sincronizar a partida: "
                                ++ Api.errorToMessage err
                                ++ " Tente sincronizar novamente ou inicie um novo jogo."
                            )
                  }
                , Cmd.none
                )


applyConfirmedSnapshot : Snapshot -> Model -> Model
applyConfirmedSnapshot snapshot model =
    let
        nextTimerRunning =
            case snapshot.status of
                Ready ->
                    False

                Playing ->
                    True

                Won ->
                    False

                Lost ->
                    False

        nextFlaggedBeforeEnd =
            if Game.isFinished snapshot.status then
                -- Preserva as bandeiras da última jogada ativa para distinguir
                -- minas acertadas com bandeira na tela de derrota.
                model.flaggedBeforeEnd

            else
                flaggedCoords snapshot
    in
    { model
        | difficulty = snapshot.difficulty
        , screen = Active snapshot
        , pending = Idle
        , timerRunning = nextTimerRunning
        , feedback = Nothing
        , focused = Board.clampCoord snapshot model.focused
        , flaggedBeforeEnd = nextFlaggedBeforeEnd
    }


flaggedCoords : Snapshot -> Set ( Int, Int )
flaggedCoords snapshot =
    snapshot.cells
        |> List.filterMap
            (\cell ->
                if cell.state == Flagged then
                    Just ( cell.row, cell.col )

                else
                    Nothing
            )
        |> Set.fromList



-- SUBSCRIPTIONS E ATALHOS GLOBAIS DE TECLADO


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ if model.timerRunning then
            Time.every 1000 (\_ -> Tick)

          else
            Sub.none
        , Browser.Events.onKeyDown (globalKeyDecoder model)
        ]


{-| Decodificador global de atalhos de teclado da interface.
Nunca intercepta combinações com Ctrl/Alt/Meta (preserva atalhos do navegador)
e ignora teclas já consumidas pelas células da grade (que usam stopPropagation).
-}
globalKeyDecoder : Model -> Decode.Decoder Msg
globalKeyDecoder model =
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
                        "1" ->
                            Decode.succeed (SelectDifficulty Easy)

                        "2" ->
                            Decode.succeed (SelectDifficulty Medium)

                        "3" ->
                            Decode.succeed (SelectDifficulty Hard)

                        "n" ->
                            Decode.succeed RestartGame

                        "N" ->
                            Decode.succeed RestartGame

                        "g" ->
                            Decode.succeed FocusBoard

                        "G" ->
                            Decode.succeed FocusBoard

                        "m" ->
                            Decode.succeed ToggleInputMode

                        "M" ->
                            Decode.succeed ToggleInputMode

                        "u" ->
                            if model.pending == SyncFailed then
                                Decode.succeed SyncGame

                            else
                                Decode.fail "sincronização não está em falha"

                        "U" ->
                            if model.pending == SyncFailed then
                                Decode.succeed SyncGame

                            else
                                Decode.fail "sincronização não está em falha"

                        "?" ->
                            Decode.succeed ToggleShortcutsHelp

                        "Escape" ->
                            if model.showShortcuts then
                                Decode.succeed HandleEscape

                            else
                                Decode.fail "nenhum painel aberto"

                        _ ->
                            Decode.fail "tecla não mapeada globalmente"
            )



-- VISUALIZAÇÃO (Frente 05 — integrada a Board.elm)


view : Model -> Html Msg
view model =
    let
        state =
            toViewState model

        isLost =
            case state.screen of
                Active snapshot ->
                    snapshot.status == Lost

                _ ->
                    False
    in
    div
        [ classList
            [ ( "app", True )
            , ( "minesweeper-app", True )
            , ( "minesweeper-app--exploded", isLost )
            ]
        ]
        [ button
            [ type_ "button"
            , class "skip-link"
            , onClick FocusBoard
            ]
            [ text "Ir para o tabuleiro (G)" ]
        , div [ class "sr-only", attribute "role" "status", attribute "aria-live" "polite" ]
            [ text state.liveAnnouncement ]
        , header [ class "topbar" ]
            [ div [ class "brand" ]
                [ h1 []
                    [ text "Campo "
                    , span [ class "accent" ] [ text "Minado" ]
                    ]
                , p [ class "subtitle" ] [ text "Motor em SWI-Prolog · Interface funcional em Elm" ]
                ]
            , Board.viewDifficultyBar
                { current = state.difficulty
                , onSelect = SelectDifficulty
                , onFocusDifficulty = \d -> FocusControl (Board.difficultyDomId d)
                }
            ]
        , main_ [ class "main-shell" ]
            [ viewHudForState state
            , Board.viewShortcutsPanel state.showShortcuts ToggleShortcutsHelp
            , viewFeedback state
            , viewBody state
            ]
        , footer [ class "footer" ]
            [ text "Primeiro clique revelado sempre seguro · Sessões mantidas em memória no servidor Prolog." ]
        , if isLost then
            Explosion.view

          else
            text ""
        ]


viewHudForState : ViewState -> Html Msg
viewHudForState state =
    let
        ( maybeStatus, maybeRevealed, maybeSafeTotal ) =
            case state.screen of
                Active snapshot ->
                    ( Just snapshot.status
                    , Just (Board.revealedSafeCount snapshot)
                    , Just (Board.safeTotal snapshot)
                    )

                _ ->
                    ( Nothing, Nothing, Nothing )
    in
    Board.viewHud
        { status = maybeStatus
        , elapsedSeconds = state.elapsedSeconds
        , remainingMines = state.remainingMines
        , revealedCount = maybeRevealed
        , safeTotal = maybeSafeTotal
        , inputMode = state.inputMode
        , isSyncing = state.pending == SyncingAfterUncertainAction
        , showShortcuts = state.showShortcuts
        , onRestart = RestartGame
        , onSetInputMode = SetInputMode
        , onFocusMode = FocusModeButton
        , onToggleShortcuts = ToggleShortcutsHelp
        }


viewFeedback : ViewState -> Html Msg
viewFeedback state =
    case state.feedback of
        Just message ->
            let
                bannerClass =
                    case state.pending of
                        SyncFailed ->
                            "banner banner--error"

                        SyncingAfterUncertainAction ->
                            "banner banner--warning"

                        _ ->
                            "banner banner--info"
            in
            div [ class bannerClass, attribute "role" "status", attribute "aria-live" "polite" ]
                [ span [] [ text message ]
                , case state.pending of
                    SyncingAfterUncertainAction ->
                        button
                            [ type_ "button"
                            , class "btn btn--ghost"
                            , disabled True
                            ]
                            [ text "Sincronizando..." ]

                    SyncFailed ->
                        div [ class "banner-actions" ]
                            [ button
                                [ type_ "button"
                                , class "btn btn--primary"
                                , attribute "aria-keyshortcuts" "u"
                                , onClick SyncGame
                                ]
                                [ text "Sincronizar novamente (U)" ]
                            , button
                                [ type_ "button"
                                , class "btn btn--ghost"
                                , attribute "aria-keyshortcuts" "n"
                                , onClick RestartGame
                                ]
                                [ text "Novo jogo (N)" ]
                            ]

                    _ ->
                        text ""
                ]

        Nothing ->
            text ""


viewBody : ViewState -> Html Msg
viewBody state =
    case state.screen of
        Loading ->
            section
                [ class "status-card screen-loading"
                , attribute "role" "status"
                , attribute "aria-live" "polite"
                ]
                [ div [ class "spinner", attribute "aria-hidden" "true" ] []
                , h2 [] [ text "Preparando partida..." ]
                , p []
                    [ text
                        ("Solicitando novo tabuleiro ("
                            ++ Game.difficultyLabel state.difficulty
                            ++ ") ao servidor Prolog."
                        )
                    ]
                ]

        Failed message ->
            section [ class "status-card status-card--error screen-error", attribute "role" "alert" ]
                [ h2 [] [ text "Não foi possível iniciar a partida" ]
                , p [] [ text message ]
                , button
                    [ type_ "button"
                    , id Board.recoveryDomId
                    , class "btn btn--primary"
                    , attribute "aria-keyshortcuts" "n"
                    , onClick RestartGame
                    ]
                    [ text "Tentar novamente (N)" ]
                ]

        SessionLost message ->
            section [ class "status-card status-card--error screen-session-lost", attribute "role" "alert" ]
                [ h2 [] [ text "Sessão da partida encerrada" ]
                , p [] [ text message ]
                , button
                    [ type_ "button"
                    , id Board.recoveryDomId
                    , class "btn btn--primary"
                    , attribute "aria-keyshortcuts" "n"
                    , onClick RestartGame
                    ]
                    [ text "Iniciar novo jogo (N)" ]
                ]

        Active snapshot ->
            section [ class "game-stage screen-active" ]
                [ Board.view
                    { snapshot = snapshot
                    , flaggedBeforeEnd = state.flaggedBeforeEnd
                    , focused = state.focused
                    , inputMode = state.inputMode
                    , isBusy = state.isBusy
                    , onPrimaryClick = PrimaryCellAction
                    , onSecondaryClick = ToggleFlag
                    , onReveal = RevealCell
                    , onToggleFlag = ToggleFlag
                    , onMoveFocus = MoveFocus
                    , onFocusRowEdge = FocusRowEdge
                    , onFocusColumnEdge = FocusColumnEdge
                    , onFocusCell = FocusCell
                    , onExitGrid = HandleEscape
                    , onToggleInputMode = ToggleInputMode
                    , onNewGame = RestartGame
                    }
                ]
