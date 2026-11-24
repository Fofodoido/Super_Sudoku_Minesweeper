module BoardTest exposing (suite)

import Api
import Board exposing (InputMode(..), VisualKind(..))
import Expect
import Game exposing (Cell, CellState(..), Difficulty(..), Snapshot, Status(..))
import Json.Decode as Decode
import Json.Encode as Encode
import Main exposing (Model, Msg(..), PendingRequest(..))
import Set
import Test exposing (Test, describe, test)


makeSnapshot : Difficulty -> Int -> Int -> Int -> Status -> List Cell -> Snapshot
makeSnapshot difficulty rows cols mineCount status cells =
    { id = "00000000-0000-4000-8000-000000000001"
    , difficulty = difficulty
    , rows = rows
    , cols = cols
    , mineCount = mineCount
    , status = status
    , revision = 1
    , cells = cells
    }


hardSnapshot : Snapshot
hardSnapshot =
    let
        cells =
            List.range 0 15
                |> List.concatMap
                    (\r ->
                        List.range 0 29
                            |> List.map (\c -> { row = r, col = c, state = Hidden })
                    )
    in
    makeSnapshot Hard 16 30 99 Ready cells


samplePlayingSnapshot : Snapshot
samplePlayingSnapshot =
    makeSnapshot Easy
        2
        3
        2
        Playing
        [ { row = 0, col = 0, state = Flagged }
        , { row = 0, col = 1, state = Hidden }
        , { row = 0, col = 2, state = Revealed 1 }
        , { row = 1, col = 0, state = Revealed 0 }
        , { row = 1, col = 1, state = Hidden }
        , { row = 1, col = 2, state = Hidden }
        ]


initActiveModel : Snapshot -> Model
initActiveModel snapshot =
    let
        ( m0, _ ) =
            Main.init Encode.null

        ( m1, _ ) =
            Main.update (CreateGameResponse m0.requestToken (Ok snapshot)) m0
    in
    m1


keyEventJson : String -> Bool -> Bool -> Bool -> String
keyEventJson key ctrl alt meta =
    Encode.object
        [ ( "key", Encode.string key )
        , ( "ctrlKey", Encode.bool ctrl )
        , ( "altKey", Encode.bool alt )
        , ( "metaKey", Encode.bool meta )
        ]
        |> Encode.encode 0


suite : Test
suite =
    describe "Frente 05 — Board, acessibilidade, grade retangular e navegação por teclado"
        [ visualKindTests
        , ariaLabelTests
        , geometryAndFormattingTests
        , mainInteractionTests
        , globalKeyboardShortcutTests
        ]


visualKindTests : Test
visualKindTests =
    describe "visualKind (inclusive bandeira incorreta na derrota)"
        [ test "bandeira durante Ready, Playing e Won permanece VisualFlagged" <|
            \_ ->
                Expect.all
                    [ \_ -> Expect.equal VisualFlagged (Board.visualKind Ready Flagged)
                    , \_ -> Expect.equal VisualFlagged (Board.visualKind Playing Flagged)
                    , \_ -> Expect.equal VisualFlagged (Board.visualKind Won Flagged)
                    ]
                    ()
        , test "bandeira em célula segura quando status é Lost vira VisualWrongFlag" <|
            \_ ->
                Expect.equal VisualWrongFlag (Board.visualKind Lost Flagged)
        , test "mina previamente marcada com bandeira na derrota vira VisualCorrectFlag" <|
            \_ ->
                let
                    flaggedSet =
                        Set.singleton ( 0, 0 )
                in
                Expect.all
                    [ \_ ->
                        Expect.equal VisualCorrectFlag
                            (Board.cellVisualKind Lost flaggedSet { row = 0, col = 0, state = Mine })
                    , \_ ->
                        Expect.equal VisualMine
                            (Board.cellVisualKind Lost flaggedSet { row = 0, col = 1, state = Mine })
                    , \_ ->
                        Expect.equal VisualExploded
                            (Board.cellVisualKind Lost flaggedSet { row = 1, col = 1, state = Exploded })
                    ]
                    ()
        , test "distingue mina comum, mina detonada e células reveladas" <|
            \_ ->
                Expect.all
                    [ \_ -> Expect.equal VisualHidden (Board.visualKind Ready Hidden)
                    , \_ -> Expect.equal (VisualRevealed 0) (Board.visualKind Playing (Revealed 0))
                    , \_ -> Expect.equal (VisualRevealed 3) (Board.visualKind Playing (Revealed 3))
                    , \_ -> Expect.equal VisualMine (Board.visualKind Lost Mine)
                    , \_ -> Expect.equal VisualExploded (Board.visualKind Lost Exploded)
                    ]
                    ()
        ]


ariaLabelTests : Test
ariaLabelTests =
    describe "cellAriaLabel (rótulos acessíveis em português, base 1)"
        [ test "descreve célula oculta, bandeira, bandeira correta e bandeira incorreta" <|
            \_ ->
                let
                    flaggedSet =
                        Set.singleton ( 0, 1 )
                in
                Expect.all
                    [ \_ ->
                        Expect.equal "Linha 1, coluna 1: oculta"
                            (Board.cellAriaLabel Playing Set.empty { row = 0, col = 0, state = Hidden })
                    , \_ ->
                        Expect.equal "Linha 2, coluna 3: marcada com bandeira"
                            (Board.cellAriaLabel Playing Set.empty { row = 1, col = 2, state = Flagged })
                    , \_ ->
                        Expect.equal "Linha 1, coluna 2: bandeira correta (mina acertada)"
                            (Board.cellAriaLabel Lost flaggedSet { row = 0, col = 1, state = Mine })
                    , \_ ->
                        Expect.equal "Linha 2, coluna 3: bandeira incorreta"
                            (Board.cellAriaLabel Lost Set.empty { row = 1, col = 2, state = Flagged })
                    ]
                    ()
        , test "trata corretamente zero, singular e plural de minas adjacentes" <|
            \_ ->
                Expect.all
                    [ \_ ->
                        Expect.equal "Linha 1, coluna 1: revelada, sem minas adjacentes"
                            (Board.cellAriaLabel Playing Set.empty { row = 0, col = 0, state = Revealed 0 })
                    , \_ ->
                        Expect.equal "Linha 1, coluna 2: revelada, 1 mina adjacente"
                            (Board.cellAriaLabel Playing Set.empty { row = 0, col = 1, state = Revealed 1 })
                    , \_ ->
                        Expect.equal "Linha 1, coluna 3: revelada, 4 minas adjacentes"
                            (Board.cellAriaLabel Playing Set.empty { row = 0, col = 2, state = Revealed 4 })
                    ]
                    ()
        , test "descreve mina e mina detonada no encerramento" <|
            \_ ->
                Expect.all
                    [ \_ ->
                        Expect.equal "Linha 3, coluna 4: mina"
                            (Board.cellAriaLabel Lost Set.empty { row = 2, col = 3, state = Mine })
                    , \_ ->
                        Expect.equal "Linha 3, coluna 5: mina detonada"
                            (Board.cellAriaLabel Lost Set.empty { row = 2, col = 4, state = Exploded })
                    ]
                    ()
        ]


geometryAndFormattingTests : Test
geometryAndFormattingTests =
    describe "Grade retangular 16×30, densidade, foco e contadores"
        [ test "agrupa 16×30 (480 células) em 16 linhas de 30 colunas" <|
            \_ ->
                let
                    rows =
                        Game.cellsByRow hardSnapshot
                in
                Expect.all
                    [ \rs -> Expect.equal 16 (List.length rs)
                    , \rs -> Expect.equal True (List.all (\r -> List.length r == 30) rs)
                    ]
                    rows
        , test "seleciona classe de densidade adequada para fácil, médio e difícil" <|
            \_ ->
                Expect.all
                    [ \_ -> Expect.equal "board--easy" (Board.boardDensityClass 9)
                    , \_ -> Expect.equal "board--medium" (Board.boardDensityClass 16)
                    , \_ -> Expect.equal "board--hard" (Board.boardDensityClass 30)
                    ]
                    ()
        , test "gera ID DOM determinístico e limita movimento de foco nos limites da grade" <|
            \_ ->
                Expect.all
                    [ \_ -> Expect.equal "ms-cell-15-29" (Board.cellDomId { row = 15, col = 29 })
                    , \_ ->
                        Expect.equal { row = 0, col = 0 }
                            (Board.moveFocus hardSnapshot -1 -1 { row = 0, col = 0 })
                    , \_ ->
                        Expect.equal { row = 15, col = 29 }
                            (Board.moveFocus hardSnapshot 5 10 { row = 15, col = 28 })
                    , \_ ->
                        Expect.equal { row = 4, col = 12 }
                            (Board.moveFocus hardSnapshot 1 -2 { row = 3, col = 14 })
                    , \_ ->
                        Expect.equal { row = 15, col = 14 }
                            (Board.moveFocusColumnEdge hardSnapshot True { row = 3, col = 14 })
                    , \_ ->
                        Expect.equal { row = 0, col = 14 }
                            (Board.moveFocusColumnEdge hardSnapshot False { row = 15, col = 14 })
                    ]
                    ()
        , test "navega ciclicamente entre dificuldades com setas esquerda/direita" <|
            \_ ->
                Expect.all
                    [ \_ -> Expect.equal Medium (Board.adjacentDifficulty 1 Easy)
                    , \_ -> Expect.equal Hard (Board.adjacentDifficulty 1 Medium)
                    , \_ -> Expect.equal Easy (Board.adjacentDifficulty 1 Hard)
                    , \_ -> Expect.equal Hard (Board.adjacentDifficulty -1 Easy)
                    ]
                    ()
        , test "formata cronômetro em MM:SS e calcula células seguras reveladas" <|
            \_ ->
                Expect.all
                    [ \_ -> Expect.equal "00:00" (Board.formatElapsed 0)
                    , \_ -> Expect.equal "00:00" (Board.formatElapsed -5)
                    , \_ -> Expect.equal "00:09" (Board.formatElapsed 9)
                    , \_ -> Expect.equal "02:05" (Board.formatElapsed 125)
                    , \_ -> Expect.equal 2 (Board.revealedSafeCount samplePlayingSnapshot)
                    , \_ -> Expect.equal 4 (Board.safeTotal samplePlayingSnapshot)
                    ]
                    ()
        ]


mainInteractionTests : Test
mainInteractionTests =
    describe "Integração com Main (modo toque/bandeira e foco por teclado)"
        [ test "PrimaryCellAction envia Reveal em RevealMode e ToggleFlag em FlagMode" <|
            \_ ->
                let
                    mRevealMode =
                        initActiveModel samplePlayingSnapshot

                    ( mAfterReveal, _ ) =
                        Main.update (PrimaryCellAction { row = 0, col = 1 }) mRevealMode

                    ( mFlagMode, _ ) =
                        Main.update ToggleInputMode mRevealMode

                    ( mAfterFlag, _ ) =
                        Main.update (PrimaryCellAction { row = 0, col = 1 }) mFlagMode
                in
                Expect.all
                    [ \_ -> Expect.equal RevealMode mRevealMode.inputMode
                    , \_ -> Expect.equal (MutatingAction (Api.Reveal { row = 0, col = 1 })) mAfterReveal.pending
                    , \_ -> Expect.equal { row = 0, col = 1 } mAfterReveal.focused
                    , \_ -> Expect.equal FlagMode mFlagMode.inputMode
                    , \_ -> Expect.equal (MutatingAction (Api.ToggleFlag { row = 0, col = 1 })) mAfterFlag.pending
                    ]
                    ()
        , test "MoveFocus, FocusRowEdge, FocusColumnEdge e RestartGame gerenciam o foco em 16×30" <|
            \_ ->
                let
                    m0 =
                        initActiveModel hardSnapshot

                    ( m1, _ ) =
                        Main.update (MoveFocus 2 3) m0

                    ( mEnd, _ ) =
                        Main.update (FocusRowEdge True) m1

                    ( mBottom, _ ) =
                        Main.update (FocusColumnEdge True) mEnd

                    ( mTop, _ ) =
                        Main.update (FocusColumnEdge False) mBottom

                    ( mHome, _ ) =
                        Main.update (FocusRowEdge False) mTop

                    ( mRestart, _ ) =
                        Main.update RestartGame mBottom
                in
                Expect.all
                    [ \_ -> Expect.equal { row = 0, col = 0 } m0.focused
                    , \_ -> Expect.equal { row = 2, col = 3 } m1.focused
                    , \_ -> Expect.equal { row = 2, col = 29 } mEnd.focused
                    , \_ -> Expect.equal { row = 15, col = 29 } mBottom.focused
                    , \_ -> Expect.equal { row = 0, col = 29 } mTop.focused
                    , \_ -> Expect.equal { row = 0, col = 0 } mHome.focused
                    , \_ -> Expect.equal { row = 0, col = 0 } mRestart.focused
                    ]
                    ()
        , test "ToggleShortcutsHelp abre o painel de atalhos e HandleEscape fecha" <|
            \_ ->
                let
                    m0 =
                        initActiveModel samplePlayingSnapshot

                    ( mOpen, _ ) =
                        Main.update ToggleShortcutsHelp m0

                    ( mClosed, _ ) =
                        Main.update HandleEscape mOpen
                in
                Expect.all
                    [ \_ -> Expect.equal False m0.showShortcuts
                    , \_ -> Expect.equal True mOpen.showShortcuts
                    , \_ -> Expect.equal False mClosed.showShortcuts
                    ]
                    ()
        , test "Main preserva flaggedBeforeEnd ao transitar de Playing para Lost e limpa no RestartGame" <|
            \_ ->
                let
                    mPlaying =
                        initActiveModel samplePlayingSnapshot

                    lostSnap =
                        { samplePlayingSnapshot
                            | status = Lost
                            , revision = 2
                            , cells =
                                [ { row = 0, col = 0, state = Mine }
                                , { row = 0, col = 1, state = Exploded }
                                , { row = 0, col = 2, state = Revealed 1 }
                                , { row = 1, col = 0, state = Revealed 0 }
                                , { row = 1, col = 1, state = Hidden }
                                , { row = 1, col = 2, state = Hidden }
                                ]
                        }

                    ( mLost, _ ) =
                        Main.update
                            (ActionResponse mPlaying.requestToken samplePlayingSnapshot.id (Ok lostSnap))
                            mPlaying

                    ( mRestarted, _ ) =
                        Main.update RestartGame mLost
                in
                Expect.all
                    [ \_ -> Expect.equal (Set.singleton ( 0, 0 )) mPlaying.flaggedBeforeEnd
                    , \_ -> Expect.equal (Set.singleton ( 0, 0 )) mLost.flaggedBeforeEnd
                    , \_ ->
                        Expect.equal VisualCorrectFlag
                            (Board.cellVisualKind Lost mLost.flaggedBeforeEnd { row = 0, col = 0, state = Mine })
                    , \_ -> Expect.equal Set.empty mRestarted.flaggedBeforeEnd
                    ]
                    ()
        ]


globalKeyboardShortcutTests : Test
globalKeyboardShortcutTests =
    describe "Atalhos globais de teclado (globalKeyDecoder)"
        [ test "mapeia 1/2/3, N, G, M e ? sem modificadores" <|
            \_ ->
                let
                    m0 =
                        initActiveModel samplePlayingSnapshot
                in
                Expect.all
                    [ \_ ->
                        Decode.decodeString (Main.globalKeyDecoder m0) (keyEventJson "1" False False False)
                            |> Expect.equal (Ok (SelectDifficulty Easy))
                    , \_ ->
                        Decode.decodeString (Main.globalKeyDecoder m0) (keyEventJson "2" False False False)
                            |> Expect.equal (Ok (SelectDifficulty Medium))
                    , \_ ->
                        Decode.decodeString (Main.globalKeyDecoder m0) (keyEventJson "3" False False False)
                            |> Expect.equal (Ok (SelectDifficulty Hard))
                    , \_ ->
                        Decode.decodeString (Main.globalKeyDecoder m0) (keyEventJson "n" False False False)
                            |> Expect.equal (Ok RestartGame)
                    , \_ ->
                        Decode.decodeString (Main.globalKeyDecoder m0) (keyEventJson "g" False False False)
                            |> Expect.equal (Ok FocusBoard)
                    , \_ ->
                        Decode.decodeString (Main.globalKeyDecoder m0) (keyEventJson "m" False False False)
                            |> Expect.equal (Ok ToggleInputMode)
                    , \_ ->
                        Decode.decodeString (Main.globalKeyDecoder m0) (keyEventJson "?" False False False)
                            |> Expect.equal (Ok ToggleShortcutsHelp)
                    ]
                    ()
        , test "nunca intercepta combinações com Ctrl, Alt ou Meta (atalhos do navegador)" <|
            \_ ->
                let
                    m0 =
                        initActiveModel samplePlayingSnapshot
                in
                Expect.all
                    [ \_ ->
                        Decode.decodeString (Main.globalKeyDecoder m0) (keyEventJson "n" True False False)
                            |> Expect.err
                    , \_ ->
                        Decode.decodeString (Main.globalKeyDecoder m0) (keyEventJson "1" False True False)
                            |> Expect.err
                    , \_ ->
                        Decode.decodeString (Main.globalKeyDecoder m0) (keyEventJson "m" False False True)
                            |> Expect.err
                    ]
                    ()
        , test "atalho U só dispara SyncGame quando pending == SyncFailed" <|
            \_ ->
                let
                    mIdle =
                        initActiveModel samplePlayingSnapshot

                    mSyncFailed =
                        { mIdle | pending = SyncFailed }
                in
                Expect.all
                    [ \_ ->
                        Decode.decodeString (Main.globalKeyDecoder mIdle) (keyEventJson "u" False False False)
                            |> Expect.err
                    , \_ ->
                        Decode.decodeString (Main.globalKeyDecoder mSyncFailed) (keyEventJson "u" False False False)
                            |> Expect.equal (Ok SyncGame)
                    ]
                    ()
        ]
