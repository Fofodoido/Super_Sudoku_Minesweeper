module Api exposing
    ( Action(..)
    , ApiError(..)
    , ApiErrorPayload
    , actionDecoder
    , cellDecoder
    , cellStateDecoder
    , createGame
    , difficultyDecoder
    , encodeAction
    , encodeCreateGame
    , errorPayloadDecoder
    , errorToMessage
    , fetchGame
    , isSessionLost
    , isUncertainOutcome
    , sendAction
    , snapshotDecoder
    , statusDecoder
    )

{-| Cliente HTTP e decoders JSON da API v1 do Campo Minado (`/api/games`).

Contrato de referência: `docs/API.md` (Frente 03).

-}

import Game exposing (Cell, CellState(..), Coord, Difficulty(..), Snapshot, Status(..))
import Http
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode


type Action
    = Reveal Coord
    | ToggleFlag Coord


type alias ApiErrorPayload =
    { code : String
    , message : String
    }


type ApiError
    = BadUrl String
    | Timeout
    | NetworkError
    | HttpError Int (Maybe ApiErrorPayload)
    | BadBody String


requestTimeoutMs : Float
requestTimeoutMs =
    10000



-- REQUISIÇÕES HTTP


createGame : Difficulty -> (Result ApiError Snapshot -> msg) -> Cmd msg
createGame difficulty toMsg =
    Http.request
        { method = "POST"
        , headers = []
        , url = "/api/games"
        , body = Http.jsonBody (encodeCreateGame difficulty)
        , expect = expectJsonWithError toMsg snapshotDecoder
        , timeout = Just requestTimeoutMs
        , tracker = Nothing
        }


fetchGame : String -> (Result ApiError Snapshot -> msg) -> Cmd msg
fetchGame gameId toMsg =
    Http.request
        { method = "GET"
        , headers = []
        , url = "/api/games/" ++ gameId
        , body = Http.emptyBody
        , expect = expectJsonWithError toMsg snapshotDecoder
        , timeout = Just requestTimeoutMs
        , tracker = Nothing
        }


sendAction : String -> Action -> (Result ApiError Snapshot -> msg) -> Cmd msg
sendAction gameId action toMsg =
    Http.request
        { method = "POST"
        , headers = []
        , url = "/api/games/" ++ gameId ++ "/actions"
        , body = Http.jsonBody (encodeAction action)
        , expect = expectJsonWithError toMsg snapshotDecoder
        , timeout = Just requestTimeoutMs
        , tracker = Nothing
        }


expectJsonWithError : (Result ApiError a -> msg) -> Decoder a -> Http.Expect msg
expectJsonWithError toMsg decoder =
    Http.expectStringResponse toMsg <|
        \response ->
            case response of
                Http.BadUrl_ url ->
                    Err (BadUrl url)

                Http.Timeout_ ->
                    Err Timeout

                Http.NetworkError_ ->
                    Err NetworkError

                Http.BadStatus_ metadata body ->
                    let
                        parsedError =
                            Decode.decodeString errorPayloadDecoder body
                                |> Result.toMaybe
                    in
                    Err (HttpError metadata.statusCode parsedError)

                Http.GoodStatus_ _ body ->
                    case Decode.decodeString decoder body of
                        Ok value ->
                            Ok value

                        Err err ->
                            Err (BadBody (Decode.errorToString err))



-- CLASSIFICAÇÃO E MENSAGENS DE ERRO EM PORTUGUÊS


isSessionLost : ApiError -> Bool
isSessionLost err =
    case err of
        HttpError 404 (Just payload) ->
            payload.code == "game_not_found"

        HttpError 404 Nothing ->
            True

        _ ->
            False


{-| Indica que a requisição pode ou não ter sido aplicada no servidor
(ex.: timeout ou queda de rede). Nesse caso, o cliente deve consultar GET
antes de liberar comandos e nunca repetir `toggle_flag` automaticamente.
-}
isUncertainOutcome : ApiError -> Bool
isUncertainOutcome err =
    case err of
        Timeout ->
            True

        NetworkError ->
            True

        _ ->
            False


errorToMessage : ApiError -> String
errorToMessage err =
    case err of
        BadUrl url ->
            "Endereço da API inválido: " ++ url

        Timeout ->
            "Tempo esgotado ao aguardar resposta do servidor."

        NetworkError ->
            "Falha de conexão com o servidor. Verifique se o backend está ativo."

        BadBody _ ->
            "Resposta inesperada recebida do servidor."

        HttpError status maybePayload ->
            case maybePayload of
                Just payload ->
                    errorCodeToMessage payload

                Nothing ->
                    if status == 404 then
                        "Partida não encontrada ou sessão expirada. Inicie um novo jogo."

                    else if status == 503 then
                        "Servidor cheio no momento. Tente novamente em instantes."

                    else
                        "Erro no servidor (HTTP " ++ String.fromInt status ++ ")."


errorCodeToMessage : ApiErrorPayload -> String
errorCodeToMessage payload =
    case payload.code of
        "game_not_found" ->
            "Sessão expirada ou partida não encontrada. Inicie um novo jogo."

        "game_over" ->
            "A partida já foi encerrada."

        "cell_flagged" ->
            "Não é possível revelar uma célula marcada com bandeira."

        "cell_revealed" ->
            "Não é possível marcar uma célula já revelada."

        "invalid_cell" ->
            "Coordenada de célula inválida."

        "invalid_difficulty" ->
            "Dificuldade selecionada não reconhecida pelo servidor."

        "invalid_action" ->
            "Ação não reconhecida pelo servidor."

        "session_limit_reached" ->
            "Limite de partidas ativas no servidor atingido. Tente novamente em breve."

        "internal_error" ->
            "Erro interno no servidor ao processar a jogada."

        _ ->
            if String.isEmpty payload.message then
                "Erro ao comunicar com o servidor (" ++ payload.code ++ ")."

            else
                payload.message



-- ENCODERS


encodeCreateGame : Difficulty -> Encode.Value
encodeCreateGame difficulty =
    Encode.object
        [ ( "difficulty", Encode.string (Game.difficultyToString difficulty) )
        ]


encodeAction : Action -> Encode.Value
encodeAction action =
    case action of
        Reveal coord ->
            Encode.object
                [ ( "action", Encode.string "reveal" )
                , ( "row", Encode.int coord.row )
                , ( "col", Encode.int coord.col )
                ]

        ToggleFlag coord ->
            Encode.object
                [ ( "action", Encode.string "toggle_flag" )
                , ( "row", Encode.int coord.row )
                , ( "col", Encode.int coord.col )
                ]



-- DECODERS


difficultyDecoder : Decoder Difficulty
difficultyDecoder =
    Decode.string
        |> Decode.andThen
            (\raw ->
                case Game.difficultyFromString raw of
                    Just difficulty ->
                        Decode.succeed difficulty

                    Nothing ->
                        Decode.fail ("Dificuldade inválida: " ++ raw)
            )


statusDecoder : Decoder Status
statusDecoder =
    Decode.string
        |> Decode.andThen
            (\raw ->
                case Game.statusFromString raw of
                    Just status ->
                        Decode.succeed status

                    Nothing ->
                        Decode.fail ("Status de partida inválido: " ++ raw)
            )


cellStateDecoder : Decoder CellState
cellStateDecoder =
    Decode.field "state" Decode.string
        |> Decode.andThen
            (\state ->
                case state of
                    "hidden" ->
                        Decode.succeed Hidden

                    "flagged" ->
                        Decode.succeed Flagged

                    "revealed" ->
                        Decode.field "adjacentMines" Decode.int
                            |> Decode.andThen
                                (\count ->
                                    if count >= 0 && count <= 8 then
                                        Decode.succeed (Revealed count)

                                    else
                                        Decode.fail ("adjacentMines fora de 0..8: " ++ String.fromInt count)
                                )

                    "mine" ->
                        Decode.succeed Mine

                    "exploded" ->
                        Decode.succeed Exploded

                    other ->
                        Decode.fail ("Estado de célula inválido: " ++ other)
            )


cellDecoder : Decoder Cell
cellDecoder =
    Decode.map3 Cell
        (Decode.field "row" nonNegativeIntDecoder)
        (Decode.field "col" nonNegativeIntDecoder)
        cellStateDecoder


snapshotDecoder : Decoder Snapshot
snapshotDecoder =
    Decode.map8 Snapshot
        (Decode.field "id" nonEmptyStringDecoder)
        (Decode.field "difficulty" difficultyDecoder)
        (Decode.field "rows" positiveIntDecoder)
        (Decode.field "cols" positiveIntDecoder)
        (Decode.field "mineCount" nonNegativeIntDecoder)
        (Decode.field "status" statusDecoder)
        (Decode.field "revision" nonNegativeIntDecoder)
        (Decode.field "cells" (Decode.list cellDecoder))
        |> Decode.andThen validateSnapshot


validateSnapshot : Snapshot -> Decoder Snapshot
validateSnapshot snapshot =
    let
        expectedCount =
            snapshot.rows * snapshot.cols

        actualCount =
            List.length snapshot.cells

        hasLeakedMine =
            not (Game.isFinished snapshot.status)
                && List.any
                    (\cell -> cell.state == Mine || cell.state == Exploded)
                    snapshot.cells
    in
    if actualCount /= expectedCount then
        Decode.fail
            ("Quantidade de células inconsistente: esperado "
                ++ String.fromInt expectedCount
                ++ ", recebido "
                ++ String.fromInt actualCount
            )

    else if hasLeakedMine then
        Decode.fail "Snapshot ativo não pode expor células mine/exploded"

    else
        Decode.succeed snapshot


errorPayloadDecoder : Decoder ApiErrorPayload
errorPayloadDecoder =
    Decode.field "error"
        (Decode.map2 ApiErrorPayload
            (Decode.field "code" Decode.string)
            (Decode.field "message" Decode.string)
        )


actionDecoder : Decoder Action
actionDecoder =
    Decode.field "action" Decode.string
        |> Decode.andThen
            (\kind ->
                case kind of
                    "reveal" ->
                        Decode.map2 (\r c -> Reveal { row = r, col = c })
                            (Decode.field "row" nonNegativeIntDecoder)
                            (Decode.field "col" nonNegativeIntDecoder)

                    "toggle_flag" ->
                        Decode.map2 (\r c -> ToggleFlag { row = r, col = c })
                            (Decode.field "row" nonNegativeIntDecoder)
                            (Decode.field "col" nonNegativeIntDecoder)

                    other ->
                        Decode.fail ("Ação inválida: " ++ other)
            )


nonEmptyStringDecoder : Decoder String
nonEmptyStringDecoder =
    Decode.string
        |> Decode.andThen
            (\s ->
                if String.isEmpty (String.trim s) then
                    Decode.fail "String vazia não permitida"

                else
                    Decode.succeed s
            )


positiveIntDecoder : Decoder Int
positiveIntDecoder =
    Decode.int
        |> Decode.andThen
            (\n ->
                if n > 0 then
                    Decode.succeed n

                else
                    Decode.fail ("Esperado inteiro positivo, recebido " ++ String.fromInt n)
            )


nonNegativeIntDecoder : Decoder Int
nonNegativeIntDecoder =
    Decode.int
        |> Decode.andThen
            (\n ->
                if n >= 0 then
                    Decode.succeed n

                else
                    Decode.fail ("Esperado inteiro não negativo, recebido " ++ String.fromInt n)
            )
