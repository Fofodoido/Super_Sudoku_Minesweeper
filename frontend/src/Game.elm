module Game exposing
    ( Cell
    , CellState(..)
    , Coord
    , Difficulty(..)
    , Dimensions
    , Snapshot
    , Status(..)
    , allDifficulties
    , canReveal
    , canToggleFlag
    , cellsByRow
    , difficultyFromString
    , difficultyLabel
    , difficultyToString
    , dimensions
    , flaggedCount
    , isFinished
    , isWrongFlag
    , remainingMines
    , statusFromString
    , statusLabel
    , statusToString
    )

{-| Domínio público do Campo Minado no cliente Elm.

O cliente consome apenas snapshots públicos devolvidos pela API Prolog; nunca
recebe lista de minas nem calcula regras de geração/expansão localmente.

-}


type Difficulty
    = Easy
    | Medium
    | Hard


type alias Dimensions =
    { rows : Int
    , cols : Int
    , mineCount : Int
    }


type Status
    = Ready
    | Playing
    | Won
    | Lost


type CellState
    = Hidden
    | Flagged
    | Revealed Int
    | Mine
    | Exploded


type alias Coord =
    { row : Int
    , col : Int
    }


type alias Cell =
    { row : Int
    , col : Int
    , state : CellState
    }


type alias Snapshot =
    { id : String
    , difficulty : Difficulty
    , rows : Int
    , cols : Int
    , mineCount : Int
    , status : Status
    , revision : Int
    , cells : List Cell
    }


allDifficulties : List Difficulty
allDifficulties =
    [ Easy, Medium, Hard ]


difficultyToString : Difficulty -> String
difficultyToString difficulty =
    case difficulty of
        Easy ->
            "easy"

        Medium ->
            "medium"

        Hard ->
            "hard"


difficultyFromString : String -> Maybe Difficulty
difficultyFromString raw =
    case raw of
        "easy" ->
            Just Easy

        "medium" ->
            Just Medium

        "hard" ->
            Just Hard

        _ ->
            Nothing


difficultyLabel : Difficulty -> String
difficultyLabel difficulty =
    case difficulty of
        Easy ->
            "Fácil (9×9)"

        Medium ->
            "Médio (16×16)"

        Hard ->
            "Difícil (16×30)"


dimensions : Difficulty -> Dimensions
dimensions difficulty =
    case difficulty of
        Easy ->
            { rows = 9, cols = 9, mineCount = 10 }

        Medium ->
            { rows = 16, cols = 16, mineCount = 40 }

        Hard ->
            { rows = 16, cols = 30, mineCount = 99 }


statusToString : Status -> String
statusToString status =
    case status of
        Ready ->
            "ready"

        Playing ->
            "playing"

        Won ->
            "won"

        Lost ->
            "lost"


statusFromString : String -> Maybe Status
statusFromString raw =
    case raw of
        "ready" ->
            Just Ready

        "playing" ->
            Just Playing

        "won" ->
            Just Won

        "lost" ->
            Just Lost

        _ ->
            Nothing


statusLabel : Status -> String
statusLabel status =
    case status of
        Ready ->
            "Pronto para começar"

        Playing ->
            "Em andamento"

        Won ->
            "Vitória!"

        Lost ->
            "Derrota"


isFinished : Status -> Bool
isFinished status =
    case status of
        Won ->
            True

        Lost ->
            True

        Ready ->
            False

        Playing ->
            False


{-| Na derrota, bandeiras em células seguras permanecem como `Flagged`.
-}
isWrongFlag : Status -> CellState -> Bool
isWrongFlag status cellState =
    status == Lost && cellState == Flagged


flaggedCount : Snapshot -> Int
flaggedCount snapshot =
    snapshot.cells
        |> List.filter (\cell -> cell.state == Flagged)
        |> List.length


remainingMines : Snapshot -> Int
remainingMines snapshot =
    snapshot.mineCount - flaggedCount snapshot


canReveal : Status -> Cell -> Bool
canReveal status cell =
    not (isFinished status) && cell.state == Hidden


canToggleFlag : Status -> Cell -> Bool
canToggleFlag status cell =
    not (isFinished status)
        && (cell.state == Hidden || cell.state == Flagged)


{-| Agrupa a lista linear (row-major) de células em linhas de tamanho `cols`
para facilitar a renderização da grade retangular pela Frente 05.
-}
cellsByRow : Snapshot -> List (List Cell)
cellsByRow snapshot =
    if snapshot.cols <= 0 then
        []

    else
        chunkList snapshot.cols snapshot.cells


chunkList : Int -> List a -> List (List a)
chunkList size items =
    case items of
        [] ->
            []

        _ ->
            List.take size items :: chunkList size (List.drop size items)
