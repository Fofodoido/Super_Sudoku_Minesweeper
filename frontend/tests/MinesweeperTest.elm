module MinesweeperTest exposing (suite)

import Api exposing (ApiError(..))
import Expect
import Game exposing (Cell, CellState(..), Difficulty(..), Snapshot, Status(..))
import Json.Decode as Decode
import Json.Encode as Encode
import Main exposing (Model, Msg(..), PendingRequest(..), ScreenState(..))
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Frente 04 — Modelo Elm, Cliente HTTP e Ciclo da Partida"
        [ decoderValidTests
        , decoderInvalidTests
        , encoderTests
        , staleResponseTests
        , concurrencyAndTimeoutRecoveryTests
        , sessionLostAndRestartTests
        , timerLifecycleTests
        ]



-- FIXTURES DE TESTE (alinhadas a docs/API.md)


readySnapshot : Snapshot
readySnapshot =
    { id = "00000000-0000-4000-8000-000000000001"
    , difficulty = Easy
    , rows = 2
    , cols = 2
    , mineCount = 1
    , status = Ready
    , revision = 0
    , cells =
        [ { row = 0, col = 0, state = Hidden }
        , { row = 0, col = 1, state = Hidden }
        , { row = 1, col = 0, state = Hidden }
        , { row = 1, col = 1, state = Hidden }
        ]
    }


playingSnapshot : Snapshot
playingSnapshot =
    { readySnapshot
        | status = Playing
        , revision = 2
        , cells =
            [ { row = 0, col = 0, state = Flagged }
            , { row = 0, col = 1, state = Revealed 1 }
            , { row = 1, col = 0, state = Hidden }
            , { row = 1, col = 1, state = Revealed 0 }
            ]
    }


lostSnapshot : Snapshot
lostSnapshot =
    { readySnapshot
        | status = Lost
        , revision = 3
        , cells =
            [ { row = 0, col = 0, state = Exploded }
            , { row = 0, col = 1, state = Flagged }
            , { row = 1, col = 0, state = Mine }
            , { row = 1, col = 1, state = Revealed 1 }
            ]
    }


wonSnapshot : Snapshot
wonSnapshot =
    { playingSnapshot
        | status = Won
        , revision = 4
    }


initActiveModel : Snapshot -> Model
initActiveModel snapshot =
    let
        ( initialModel, _ ) =
            Main.init Encode.null

        ( activeModel, _ ) =
            Main.update (CreateGameResponse initialModel.requestToken (Ok snapshot)) initialModel
    in
    activeModel



-- 1. DECODERS VÁLIDOS


decoderValidTests : Test
decoderValidTests =
    describe "Decoders válidos"
        [ test "decodifica snapshot ready com células hidden" <|
            \_ ->
                let
                    json =
                        """
                        {
                          "id": "00000000-0000-4000-8000-000000000001",
                          "difficulty": "easy",
                          "rows": 2,
                          "cols": 2,
                          "mineCount": 1,
                          "status": "ready",
                          "revision": 0,
                          "cells": [
                            { "row": 0, "col": 0, "state": "hidden" },
                            { "row": 0, "col": 1, "state": "hidden" },
                            { "row": 1, "col": 0, "state": "hidden" },
                            { "row": 1, "col": 1, "state": "hidden" }
                          ]
                        }
                        """
                in
                Decode.decodeString Api.snapshotDecoder json
                    |> Expect.equal (Ok readySnapshot)
        , test "decodifica snapshot playing com flagged e revealed" <|
            \_ ->
                let
                    json =
                        """
                        {
                          "id": "00000000-0000-4000-8000-000000000001",
                          "difficulty": "easy",
                          "rows": 2,
                          "cols": 2,
                          "mineCount": 1,
                          "status": "playing",
                          "revision": 2,
                          "cells": [
                            { "row": 0, "col": 0, "state": "flagged" },
                            { "row": 0, "col": 1, "state": "revealed", "adjacentMines": 1 },
                            { "row": 1, "col": 0, "state": "hidden" },
                            { "row": 1, "col": 1, "state": "revealed", "adjacentMines": 0 }
                          ]
                        }
                        """
                in
                Decode.decodeString Api.snapshotDecoder json
                    |> Expect.equal (Ok playingSnapshot)
        , test "decodifica snapshot lost e identifica bandeira incorreta" <|
            \_ ->
                let
                    json =
                        """
                        {
                          "id": "00000000-0000-4000-8000-000000000001",
                          "difficulty": "easy",
                          "rows": 2,
                          "cols": 2,
                          "mineCount": 1,
                          "status": "lost",
                          "revision": 3,
                          "cells": [
                            { "row": 0, "col": 0, "state": "exploded" },
                            { "row": 0, "col": 1, "state": "flagged" },
                            { "row": 1, "col": 0, "state": "mine" },
                            { "row": 1, "col": 1, "state": "revealed", "adjacentMines": 1 }
                          ]
                        }
                        """
                in
                case Decode.decodeString Api.snapshotDecoder json of
                    Ok snap ->
                        Expect.all
                            [ \_ -> Expect.equal lostSnapshot snap
                            , \_ -> Expect.equal True (Game.isWrongFlag snap.status Flagged)
                            , \_ -> Expect.equal False (Game.isWrongFlag snap.status Mine)
                            ]
                            ()

                    Err err ->
                        Expect.fail (Decode.errorToString err)
        , test "decodifica payload de erro da API" <|
            \_ ->
                let
                    json =
                        """
                        {
                          "error": {
                            "code": "invalid_cell",
                            "message": "Coordenadas ausentes, inválidas ou fora do tabuleiro"
                          }
                        }
                        """
                in
                Decode.decodeString Api.errorPayloadDecoder json
                    |> Expect.equal
                        (Ok
                            { code = "invalid_cell"
                            , message = "Coordenadas ausentes, inválidas ou fora do tabuleiro"
                            }
                        )
        ]



-- 2. DECODERS INVÁLIDOS


decoderInvalidTests : Test
decoderInvalidTests =
    describe "Decoders inválidos"
        [ test "rejeita dificuldade desconhecida" <|
            \_ ->
                Decode.decodeString Api.difficultyDecoder "\"insane\""
                    |> Expect.err
        , test "rejeita status desconhecido" <|
            \_ ->
                Decode.decodeString Api.statusDecoder "\"paused\""
                    |> Expect.err
        , test "rejeita célula revealed sem adjacentMines" <|
            \_ ->
                Decode.decodeString Api.cellDecoder """{ "row": 0, "col": 0, "state": "revealed" }"""
                    |> Expect.err
        , test "rejeita célula revealed com adjacentMines fora de 0..8" <|
            \_ ->
                Decode.decodeString Api.cellDecoder """{ "row": 0, "col": 0, "state": "revealed", "adjacentMines": 9 }"""
                    |> Expect.err
        , test "rejeita snapshot com quantidade de células diferente de rows * cols" <|
            \_ ->
                let
                    json =
                        """
                        {
                          "id": "00000000-0000-4000-8000-000000000001",
                          "difficulty": "easy",
                          "rows": 2,
                          "cols": 2,
                          "mineCount": 1,
                          "status": "ready",
                          "revision": 0,
                          "cells": [
                            { "row": 0, "col": 0, "state": "hidden" }
                          ]
                        }
                        """
                in
                Decode.decodeString Api.snapshotDecoder json
                    |> Expect.err
        , test "rejeita vazamento de mine/exploded em partida ativa (playing)" <|
            \_ ->
                let
                    json =
                        """
                        {
                          "id": "00000000-0000-4000-8000-000000000001",
                          "difficulty": "easy",
                          "rows": 1,
                          "cols": 1,
                          "mineCount": 1,
                          "status": "playing",
                          "revision": 1,
                          "cells": [
                            { "row": 0, "col": 0, "state": "mine" }
                          ]
                        }
                        """
                in
                Decode.decodeString Api.snapshotDecoder json
                    |> Expect.err
        ]



-- 3. ENCODERS


encoderTests : Test
encoderTests =
    describe "Encoders de requisição"
        [ test "serializa criação de partida" <|
            \_ ->
                Api.encodeCreateGame Medium
                    |> Encode.encode 0
                    |> Expect.equal "{\"difficulty\":\"medium\"}"
        , test "serializa ação reveal" <|
            \_ ->
                Api.encodeAction (Api.Reveal { row = 4, col = 3 })
                    |> Decode.decodeValue Api.actionDecoder
                    |> Expect.equal (Ok (Api.Reveal { row = 4, col = 3 }))
        , test "serializa ação toggle_flag" <|
            \_ ->
                Api.encodeAction (Api.ToggleFlag { row = 0, col = 2 })
                    |> Decode.decodeValue Api.actionDecoder
                    |> Expect.equal (Ok (Api.ToggleFlag { row = 0, col = 2 }))
        ]



-- 4. RESPOSTAS ATRASADAS DE PARTIDA ANTIGA


staleResponseTests : Test
staleResponseTests =
    describe "Descarte de respostas atrasadas"
        [ test "ignora CreateGameResponse de token antigo após novo jogo" <|
            \_ ->
                let
                    ( m0, _ ) =
                        Main.init Encode.null

                    oldToken =
                        m0.requestToken

                    ( m1, _ ) =
                        Main.update (SelectDifficulty Hard) m0

                    ( m2, _ ) =
                        Main.update (CreateGameResponse oldToken (Ok readySnapshot)) m1
                in
                Expect.all
                    [ \m -> Expect.equal Loading m.screen
                    , \m -> Expect.equal Hard m.difficulty
                    , \m -> Expect.equal CreatingGame m.pending
                    ]
                    m2
        , test "ignora ActionResponse de partida antiga após reiniciar" <|
            \_ ->
                let
                    mActive =
                        initActiveModel readySnapshot

                    oldToken =
                        mActive.requestToken

                    ( mRestarted, _ ) =
                        Main.update RestartGame mActive

                    ( mAfterStale, _ ) =
                        Main.update (ActionResponse oldToken readySnapshot.id (Ok playingSnapshot)) mRestarted
                in
                Expect.all
                    [ \m -> Expect.equal Loading m.screen
                    , \m -> Expect.equal CreatingGame m.pending
                    ]
                    mAfterStale
        , test "ignora SyncResponse de gameId antigo mesmo com token atual" <|
            \_ ->
                let
                    mActive =
                        initActiveModel readySnapshot

                    ( mAfterStaleSync, _ ) =
                        Main.update
                            (SyncResponse mActive.requestToken "id-de-outra-partida" (Ok lostSnapshot))
                            mActive
                in
                Expect.equal (Active readySnapshot) mAfterStaleSync.screen
        ]



-- 5. BLOQUEIO CONCORRENTE E RECUPERAÇÃO APÓS TIMEOUT


concurrencyAndTimeoutRecoveryTests : Test
concurrencyAndTimeoutRecoveryTests =
    describe "Concorrência e recuperação após resultado incerto"
        [ test "permite apenas uma ação mutante pendente por vez" <|
            \_ ->
                let
                    m0 =
                        initActiveModel readySnapshot

                    ( m1, _ ) =
                        Main.update (RevealCell { row = 0, col = 1 }) m0

                    ( m2, cmd2 ) =
                        Main.update (ToggleFlag { row = 0, col = 0 }) m1
                in
                Expect.all
                    [ \_ -> Expect.equal (MutatingAction (Api.Reveal { row = 0, col = 1 })) m1.pending
                    , \_ -> Expect.equal m1 m2
                    , \_ -> Expect.equal Cmd.none cmd2
                    ]
                    ()
        , test "em timeout de toggle_flag, entra em sincronização via GET e só libera após SyncResponse" <|
            \_ ->
                let
                    m0 =
                        initActiveModel readySnapshot

                    ( m1, _ ) =
                        Main.update (ToggleFlag { row = 0, col = 0 }) m0

                    -- Timeout: não repete toggle_flag; muda para SyncingAfterUncertainAction e dispara GET
                    ( m2, _ ) =
                        Main.update (ActionResponse m1.requestToken readySnapshot.id (Err Timeout)) m1

                    -- Enquanto sincroniza, novas jogadas continuam bloqueadas
                    ( mBlocked, cmdBlocked ) =
                        Main.update (RevealCell { row = 1, col = 1 }) m2

                    -- Quando GET volta com estado confirmado, libera o tabuleiro
                    ( mSynced, _ ) =
                        Main.update (SyncResponse m2.requestToken readySnapshot.id (Ok playingSnapshot)) m2
                in
                Expect.all
                    [ \_ -> Expect.equal SyncingAfterUncertainAction m2.pending
                    , \_ -> Expect.notEqual Nothing m2.feedback
                    , \_ -> Expect.equal m2 mBlocked
                    , \_ -> Expect.equal Cmd.none cmdBlocked
                    , \_ -> Expect.equal Idle mSynced.pending
                    , \_ -> Expect.equal (Active playingSnapshot) mSynced.screen
                    , \_ -> Expect.equal Nothing mSynced.feedback
                    ]
                    ()
        , test "se a sincronização via GET também falhar por rede, mantém comandos bloqueados" <|
            \_ ->
                let
                    m0 =
                        initActiveModel readySnapshot

                    ( m1, _ ) =
                        Main.update (ToggleFlag { row = 0, col = 0 }) m0

                    ( m2, _ ) =
                        Main.update (ActionResponse m1.requestToken readySnapshot.id (Err NetworkError)) m1

                    ( m3, _ ) =
                        Main.update (SyncResponse m2.requestToken readySnapshot.id (Err NetworkError)) m2
                in
                Expect.all
                    [ \_ -> Expect.equal SyncingAfterUncertainAction m3.pending
                    , \_ -> Expect.notEqual Nothing m3.feedback
                    ]
                    ()
        ]



-- 6. SESSÃO PERDIDA E REINÍCIO NA MESMA DIFICULDADE


sessionLostAndRestartTests : Test
sessionLostAndRestartTests =
    describe "Sessão perdida e reinício"
        [ test "trata 404 game_not_found como SessionLost e para o cronômetro" <|
            \_ ->
                let
                    m0 =
                        initActiveModel playingSnapshot

                    ( m1, _ ) =
                        Main.update (RevealCell { row = 1, col = 0 }) m0

                    notFoundErr =
                        HttpError 404 (Just { code = "game_not_found", message = "Partida expirada" })

                    ( m2, _ ) =
                        Main.update (ActionResponse m1.requestToken playingSnapshot.id (Err notFoundErr)) m1
                in
                Expect.all
                    [ \_ ->
                        case m2.screen of
                            SessionLost _ ->
                                Expect.pass

                            _ ->
                                Expect.fail "Esperava ScreenState SessionLost"
                    , \_ -> Expect.equal False m2.timerRunning
                    , \_ -> Expect.equal Idle m2.pending
                    ]
                    ()
        , test "RestartGame cria nova partida mantendo a mesma dificuldade" <|
            \_ ->
                let
                    mediumSnap =
                        { readySnapshot | difficulty = Medium }

                    m0 =
                        initActiveModel mediumSnap

                    ( m1, _ ) =
                        Main.update RestartGame m0
                in
                Expect.all
                    [ \_ -> Expect.equal Medium m1.difficulty
                    , \_ -> Expect.equal Loading m1.screen
                    , \_ -> Expect.equal CreatingGame m1.pending
                    , \_ -> Expect.equal (m0.requestToken + 1) m1.requestToken
                    ]
                    ()
        ]



-- 7. CRONÔMETRO LOCAL


timerLifecycleTests : Test
timerLifecycleTests =
    describe "Ciclo do cronômetro local"
        [ test "não inicia em Ready, inicia na 1ª revelação confirmada (Playing) e para em Won/Lost" <|
            \_ ->
                let
                    mReady =
                        initActiveModel readySnapshot

                    ( mReadyTick, _ ) =
                        Main.update Tick mReady

                    -- 1ª revelação confirmada muda status para Playing
                    ( mPlaying, _ ) =
                        Main.update (ActionResponse mReady.requestToken readySnapshot.id (Ok playingSnapshot)) mReady

                    ( mTick1, _ ) =
                        Main.update Tick mPlaying

                    ( mTick2, _ ) =
                        Main.update Tick mTick1

                    -- Vitória congela cronômetro
                    ( mWon, _ ) =
                        Main.update (ActionResponse mTick2.requestToken playingSnapshot.id (Ok wonSnapshot)) mTick2

                    ( mWonTick, _ ) =
                        Main.update Tick mWon
                in
                Expect.all
                    [ \_ -> Expect.equal False mReady.timerRunning
                    , \_ -> Expect.equal 0 mReadyTick.elapsedSeconds
                    , \_ -> Expect.equal True mPlaying.timerRunning
                    , \_ -> Expect.equal 2 mTick2.elapsedSeconds
                    , \_ -> Expect.equal False mWon.timerRunning
                    , \_ -> Expect.equal 2 mWonTick.elapsedSeconds
                    ]
                    ()
        ]
