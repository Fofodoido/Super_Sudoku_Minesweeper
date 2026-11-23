module Main exposing
    ( Model
    , Msg(..)
    , PendingRequest(..)
    , ScreenState(..)
    , ViewState
    , init
    , isBusy
    , main
    , subscriptions
    , toViewState
    , update
    , view
    )

{-| Coordenação da partida de Campo Minado (Frente 04).

Responsável pelo modelo TEA, ciclo de vida das requisições HTTP, bloqueio de
ações concorrentes, descarte de respostas de partidas antigas, recuperação via
GET após timeout/falha incerta, tratamento de sessão perdida e cronômetro local.

Os tipos, mensagens e `ViewState` são expostos para integração direta da
interface pela Frente 05 (`Board.elm`).

-}

import Api exposing (Action(..), ApiError)
import Browser
import Explosion
import Game exposing (Cell, CellState(..), Coord, Difficulty(..), Snapshot, Status(..))
import Html exposing (Html, button, div, h1, header, main_, p, section, span, text)
import Html.Attributes exposing (attribute, class, disabled, style, title, type_)
import Html.Events exposing (onClick, preventDefaultOn)
import Json.Decode as Decode
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
    }


{-| Projeção de leitura para componentes de interface (Frente 05):
grade, seletor de dificuldade, contador de minas, cronômetro e resultado.
-}
type alias ViewState =
    { difficulty : Difficulty
    , screen : ScreenState
    , pending : PendingRequest
    , isBusy : Bool
    , elapsedSeconds : Int
    , remainingMines : Maybe Int
    , feedback : Maybe String
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
        }



-- MENSAGENS


type Msg
    = SelectDifficulty Difficulty
    | RestartGame
    | RevealCell Coord
    | ToggleFlag Coord
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
                        ( { model
                            | difficulty = snapshot.difficulty
                            , screen = Active snapshot
                            , pending = Idle
                            , elapsedSeconds = 0
                            , timerRunning = snapshot.status == Playing
                            , feedback = Nothing
                          }
                        , Cmd.none
                        )

                    Err err ->
                        ( { model
                            | screen = Failed (Api.errorToMessage err)
                            , pending = Idle
                            , timerRunning = False
                            , feedback = Nothing
                          }
                        , Cmd.none
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
                , Cmd.none
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
                , Cmd.none
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
    in
    { model
        | difficulty = snapshot.difficulty
        , screen = Active snapshot
        , pending = Idle
        , timerRunning = nextTimerRunning
        , feedback = Nothing
    }



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    if model.timerRunning then
        Time.every 1000 (\_ -> Tick)

    else
        Sub.none



-- VISUALIZAÇÃO BASE (será estilizada/estendida pela Frente 05 em Board.elm)


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
    main_
        [ class
            (if isLost then
                "minesweeper-app minesweeper-app--exploded"

             else
                "minesweeper-app"
            )
        ]
        [ Explosion.styles
        , header [ class "minesweeper-header" ]
            [ h1 [] [ text "Campo Minado" ]
            , viewControls state
            ]
        , viewFeedback state
        , viewBody state
        , if isLost then
            Explosion.view

          else
            text ""
        ]


viewControls : ViewState -> Html Msg
viewControls state =
    div [ class "minesweeper-controls" ]
        [ div [ class "difficulty-selector" ]
            (List.map (viewDifficultyButton state.difficulty) Game.allDifficulties)
        , div [ class "status-bar" ]
            [ span [ class "mine-counter" ]
                [ text
                    ("Minas: "
                        ++ (state.remainingMines
                                |> Maybe.map String.fromInt
                                |> Maybe.withDefault "--"
                           )
                    )
                ]
            , span [ class "timer", style "margin" "0 0.75rem" ]
                [ text ("Tempo: " ++ String.fromInt state.elapsedSeconds ++ "s") ]
            , button
                [ type_ "button"
                , class "restart-button"
                , style "color" "#111"
                , style "padding" "0.25rem 0.6rem"
                , onClick RestartGame
                ]
                [ text "Novo jogo" ]
            ]
        ]


viewDifficultyButton : Difficulty -> Difficulty -> Html Msg
viewDifficultyButton current difficulty =
    button
        [ type_ "button"
        , class
            (if current == difficulty then
                "difficulty-button difficulty-button--active"

             else
                "difficulty-button"
            )
        , style "color" "#111"
        , style "padding" "0.25rem 0.6rem"
        , style "margin-right" "0.25rem"
        , onClick (SelectDifficulty difficulty)
        ]
        [ text (Game.difficultyLabel difficulty) ]


viewFeedback : ViewState -> Html Msg
viewFeedback state =
    case state.feedback of
        Just message ->
            div [ class "feedback-banner", attribute "role" "status" ]
                [ p [] [ text message ]
                , case state.pending of
                    SyncingAfterUncertainAction ->
                        button
                            [ type_ "button"
                            , style "color" "#111"
                            , disabled True
                            ]
                            [ text "Sincronizando..." ]

                    SyncFailed ->
                        button
                            [ type_ "button"
                            , style "color" "#111"
                            , onClick SyncGame
                            ]
                            [ text "Sincronizar novamente" ]

                    _ ->
                        text ""
                ]

        Nothing ->
            text ""


viewBody : ViewState -> Html Msg
viewBody state =
    case state.screen of
        Loading ->
            section [ class "screen-loading" ]
                [ p [] [ text "Carregando nova partida..." ] ]

        Failed message ->
            section [ class "screen-error" ]
                [ p [] [ text message ]
                , button [ type_ "button", style "color" "#111", onClick RestartGame ] [ text "Tentar novamente" ]
                ]

        SessionLost message ->
            section [ class "screen-session-lost" ]
                [ p [] [ text message ]
                , button [ type_ "button", style "color" "#111", onClick RestartGame ] [ text "Iniciar novo jogo" ]
                ]

        Active snapshot ->
            section [ class "screen-active" ]
                [ p [ class "game-status" ] [ text (Game.statusLabel snapshot.status) ]
                , viewBoard state.isBusy snapshot
                ]


viewBoard : Bool -> Snapshot -> Html Msg
viewBoard busy snapshot =
    div
        [ class "minesweeper-board"
        , style "display" "grid"
        , style "grid-template-columns" ("repeat(" ++ String.fromInt snapshot.cols ++ ", 2rem)")
        , style "gap" "2px"
        ]
        (List.map (viewCell busy snapshot.status) snapshot.cells)


viewCell : Bool -> Status -> Cell -> Html Msg
viewCell busy status cell =
    let
        coord =
            { row = cell.row, col = cell.col }

        ( label, bgColor, textColor ) =
            case cell.state of
                Hidden ->
                    ( "", "#4b5563", "#f9fafb" )

                Flagged ->
                    if Game.isWrongFlag status cell.state then
                        ( "✕", "#7f1d1d", "#fecaca" )

                    else
                        ( "⚑", "#4b5563", "#facc15" )

                Revealed 0 ->
                    ( "", "#1f2937", "#e5e7eb" )

                Revealed n ->
                    ( String.fromInt n, "#1f2937", "#e5e7eb" )

                Mine ->
                    ( "💣", "#374151", "#f9fafb" )

                Exploded ->
                    ( "💥", "#991b1b", "#ffffff" )

        onRightClick =
            preventDefaultOn "contextmenu" (Decode.succeed ( ToggleFlag coord, True ))
    in
    button
        [ type_ "button"
        , class
            (if cell.state == Exploded then
                "board-cell board-cell--exploded"

             else
                "board-cell"
            )
        , style "width" "2rem"
        , style "height" "2rem"
        , style "padding" "0"
        , style "background-color" bgColor
        , style "color" textColor
        , style "border" "1px solid #374151"
        , disabled (busy || Game.isFinished status)
        , onClick (RevealCell coord)
        , onRightClick
        , title ("Linha " ++ String.fromInt (cell.row + 1) ++ ", Coluna " ++ String.fromInt (cell.col + 1))
        ]
        [ text label ]
