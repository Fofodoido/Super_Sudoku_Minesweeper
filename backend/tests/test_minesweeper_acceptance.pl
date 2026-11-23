:- encoding(utf8).
:- use_module(library(plunit)).
:- use_module(library(http/http_open)).
:- use_module(library(http/http_json)).
:- use_module(library(http/thread_httpd)).
:- use_module(library(json)).
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(aggregate)).
:- use_module('../server').
:- use_module('../minesweeper/sessions').
:- use_module('../minesweeper/board').

acceptance_setup(Port) :-
    reset_sessions,
    reset_session_config,
    server:start(Port).

acceptance_cleanup(Port) :-
    http_stop_server(Port, []),
    reset_sessions,
    reset_session_config.

url(Port, Path, URL) :-
    format(atom(URL), 'http://127.0.0.1:~w~w', [Port, Path]).

api(Port, Method, Path, Body, Status, Dict, Raw) :-
    url(Port, Path, URL),
    (   Body == none
    ->  Options = [method(Method)]
    ;   Options = [method(Method), post(json(Body))]
    ),
    setup_call_cleanup(
        http_open(URL, Stream, [status_code(Status) | Options]),
        read_string(Stream, _, Raw),
        close(Stream)),
    atom_json_dict(Raw, Dict, [value_string_as(string)]).

create(Port, Difficulty, Snapshot) :-
    api(Port, post, '/api/games', _{difficulty: Difficulty}, Status, Snapshot, Raw),
    assertion(Status == 201),
    check_response(Snapshot, Raw).

fetch(Port, Id, Snapshot) :-
    game_path(Id, '', Path),
    api(Port, get, Path, none, Status, Snapshot, Raw),
    assertion(Status == 200),
    check_response(Snapshot, Raw).

act(Port, Id, Action, Row-Col, Status, Reply) :-
    game_path(Id, '/actions', Path),
    api(Port, post, Path, _{action: Action, row: Row, col: Col},
        Status, Reply, Raw),
    (   Status == 200
    ->  check_response(Reply, Raw)
    ;   true
    ).

act_ok(Port, Id, Action, Cell, Snapshot) :-
    act(Port, Id, Action, Cell, Status, Snapshot),
    assertion(Status == 200).

game_path(Id, Suffix, Path) :-
    format(atom(Path), '/api/games/~w~w', [Id, Suffix]).

check_response(Snapshot, Raw) :-
    assertion(snapshot_shape(Snapshot)),
    (   active(Snapshot)
    ->  assert_no_hidden_data(Snapshot, Raw)
    ;   true
    ).

snapshot_shape(S) :-
    string(S.id), string(S.difficulty), string(S.status),
    integer(S.rows), integer(S.cols), integer(S.mineCount),
    integer(S.revision), S.revision >= 0,
    length(S.cells, N), N =:= S.rows * S.cols,
    cells_in_row_order(S.cells, S.cols).

cells_in_row_order(Cells, Cols) :-
    cells_in_row_order(Cells, Cols, 0).

cells_in_row_order([], _, _).
cells_in_row_order([C|Cs], Cols, I) :-
    get_dict(row, C, Row), Row =:= I // Cols,
    get_dict(col, C, Col), Col =:= I mod Cols,
    I1 is I + 1,
    cells_in_row_order(Cs, Cols, I1).

active(S) :- memberchk(S.status, ["ready", "playing"]).

assert_no_hidden_data(S, Raw) :-
    forall(member(Forbidden, ["\"mine\"", "\"exploded\"", "\"mines\"",
                              "\"seed\"", "\"solution\""]),
           assertion(\+ sub_string(Raw, _, _, _, Forbidden))),
    forall(member(Key, [mines, seed, solution]),
           assertion(\+ get_dict(Key, S, _))),
    forall(member(C, S.cells),
           ( assertion(memberchk(C.state, ["hidden", "flagged", "revealed"])),
             (   C.state == "revealed"
             ->  assertion(between(0, 8, C.adjacentMines))
             ;   assertion(\+ get_dict(adjacentMines, C, _))
             )
           )).

all_hidden(S) :-
    forall(member(C, S.cells), C.state == "hidden").

state_at(S, Row-Col, State) :-
    member(C, S.cells), C.row =:= Row, C.col =:= Col, !,
    State = C.state.

cells_with_state(S, State, Cells) :-
    findall(R-C, ( member(Cell, S.cells), Cell.state == State,
                   R = Cell.row, C = Cell.col ),
            Cells).

count_state(S, State, N) :-
    aggregate_all(count, (member(C, S.cells), C.state == State), N).

oracle_mines(Id, Mines) :-
    atom_string(IdAtom, Id),
    minesweeper_sessions:game_session(IdAtom, Game, _),
    arg(7, Game, generated(CellMines)),
    findall(R-C, member(cell(R, C), CellMines), Mines).

assert_numbers_match(S, Mines) :-
    findall(cell(R, C), member(R-C, Mines), CellMines),
    forall(( member(C, S.cells), C.state == "revealed" ),
           ( adjacent_mines(S.rows, S.cols, CellMines, cell(C.row, C.col), N),
             assertion(C.adjacentMines =:= N),
             assertion(\+ memberchk(C.row-C.col, Mines))
           )).

center(S, Row-Col) :-
    Row is S.rows // 2,
    Col is S.cols // 2.

play_to_win(_, _, S, _, S) :-
    S.status == "won", !.
play_to_win(Port, Id, S0, Mines, Final) :-
    assertion(S0.status == "playing"),
    member(C, S0.cells), C.state == "hidden",
    Cell = C.row-C.col, \+ memberchk(Cell, Mines), !,
    act_ok(Port, Id, "reveal", Cell, S1),
    assertion(S1.revision =:= S0.revision + 1),
    assertion(state_at(S1, Cell, "revealed")),
    (   active(S1)
    ->  assert_numbers_match(S1, Mines)
    ;   true
    ),
    play_to_win(Port, Id, S1, Mines, Final).

started_game(Port, Difficulty, Id, Snapshot) :-
    between(1, 10, _),
    create(Port, Difficulty, S0),
    center(S0, First),
    act_ok(Port, S0.id, "reveal", First, S1),
    S1.status == "playing",
    !,
    Id = S1.id,
    Snapshot = S1.

assert_final_board(S, Mines, Exploded) :-
    length(Mines, NMines),
    assertion(NMines =:= S.mineCount),
    forall(member(Cell, Mines),
           (   Cell == Exploded
           ->  assertion(state_at(S, Cell, "exploded"))
           ;   assertion(state_at(S, Cell, "mine"))
           )),
    count_state(S, "mine", NM),
    count_state(S, "exploded", NE),
    assertion(NM + NE =:= NMines).

assert_locked(Port, Id, Final) :-
    forall(member(Action-Cell, ["reveal"-(0-0), "toggle_flag"-(0-0)]),
           ( act(Port, Id, Action, Cell, Status, Error),
             assertion(Status == 409),
             assertion(Error.error.code == "game_over")
           )),
    fetch(Port, Id, Again),
    assertion(Again =@= Final).

assert_restart(Port, Old) :-
    create(Port, Old.difficulty, New),
    assertion(New.id \== Old.id),
    assertion(New.status == "ready"),
    assertion(New.revision == 0),
    assertion(all_hidden(New)),
    assertion(New.rows-New.cols-New.mineCount == Old.rows-Old.cols-Old.mineCount),
    fetch(Port, Old.id, OldAgain),
    assertion(OldAgain =@= Old).

:- begin_tests(minesweeper_acceptance).

test(win_flow,
     [ forall(preset(Diff, Rows, Cols, MineCount)),
       setup(acceptance_setup(Port)), cleanup(acceptance_cleanup(Port))
     ]) :-
    atom_string(Diff, DiffS),
    create(Port, DiffS, S0),
    assertion(S0.difficulty-S0.rows-S0.cols-S0.mineCount
              == DiffS-Rows-Cols-MineCount),
    assertion(S0.status-S0.revision == "ready"-0),
    assertion(all_hidden(S0)),
    Id = S0.id,
    assertion(\+ oracle_mines(Id, _)),

    act_ok(Port, Id, "toggle_flag", 0-0, S1),
    assertion(S1.status-S1.revision == "ready"-1),
    assertion(state_at(S1, 0-0, "flagged")),
    assertion(\+ oracle_mines(Id, _)),

    center(S1, First),
    act_ok(Port, Id, "reveal", First, S2),
    assertion(S2.revision == 2),
    oracle_mines(Id, Mines),
    assertion(\+ memberchk(First, Mines)),
    assertion(state_at(S2, First, "revealed")),
    assert_numbers_match(S2, Mines),

    once(( member(C2, S2.cells), C2.row-C2.col == First )),
    (   C2.adjacentMines =:= 0
    ->  count_state(S2, "revealed", Opened),
        assertion(Opened > 1)
    ;   true
    ),

    (   active(S2)
    ->  act_ok(Port, Id, "reveal", First, S2b),
        assertion(S2b =@= S2)
    ;   true
    ),

    (   ( memberchk(0-0, Mines) ; S2.status == "won" )
    ->  S3 = S2
    ;   act_ok(Port, Id, "toggle_flag", 0-0, S3),
        assertion(state_at(S3, 0-0, "hidden"))
    ),
    play_to_win(Port, Id, S3, Mines, Won),
    assertion(Won.status == "won"),
    count_state(Won, "revealed", Safe),
    assertion(Safe =:= Rows * Cols - MineCount),
    assert_final_board(Won, Mines, none),
    assert_locked(Port, Id, Won),
    assert_restart(Port, Won).

test(loss_flow,
     [ forall(preset(Diff, _, _, _)),
       setup(acceptance_setup(Port)), cleanup(acceptance_cleanup(Port))
     ]) :-
    atom_string(Diff, DiffS),
    started_game(Port, DiffS, Id, S1),
    oracle_mines(Id, Mines),
    Mines = [FlaggedMine, Boom | _],
    cells_with_state(S1, "hidden", Hidden),
    once(( member(WrongFlag, Hidden), \+ memberchk(WrongFlag, Mines) )),
    act_ok(Port, Id, "toggle_flag", FlaggedMine, S2),
    act_ok(Port, Id, "toggle_flag", WrongFlag, S3),
    assertion(S3.revision =:= S1.revision + 2),

    act(Port, Id, "reveal", FlaggedMine, Blocked, BlockedErr),
    assertion(Blocked == 409),
    assertion(BlockedErr.error.code == "cell_flagged"),
    fetch(Port, Id, S3b),
    assertion(S3b =@= S3),
    assertion(S2.status == "playing"),

    act_ok(Port, Id, "reveal", Boom, Lost),
    assertion(Lost.status == "lost"),
    assertion(Lost.revision =:= S3.revision + 1),
    assert_final_board(Lost, Mines, Boom),
    assertion(state_at(Lost, WrongFlag, "flagged")),
    assert_locked(Port, Id, Lost),
    assert_restart(Port, Lost).

test(network_failure_recovery,
     [ setup(acceptance_setup(Port)), cleanup(acceptance_cleanup(Port)) ]) :-
    create(Port, "easy", S0),
    Id = S0.id,
    act_ok(Port, Id, "toggle_flag", 0-0, Lost1),   % resposta "perdida"
    fetch(Port, Id, Recovered),
    assertion(Recovered =@= Lost1),
    assertion(Recovered.revision == 1),
    act_ok(Port, Id, "toggle_flag", 0-0, Replayed),
    assertion(state_at(Replayed, 0-0, "hidden")),
    assertion(Replayed.revision == 2),
    fetch(Port, Id, Again),
    assertion(Again =@= Replayed).

test(expired_session_mid_game,
     [ setup(acceptance_setup(Port)), cleanup(acceptance_cleanup(Port)) ]) :-
    configure_sessions([now(1000)]),
    create(Port, "medium", S0),
    Id = S0.id,
    center(S0, First),
    act_ok(Port, Id, "reveal", First, _),
    configure_sessions([now(8199)]),
    fetch(Port, Id, Alive),
    assertion(Alive.status == "playing"),
    configure_sessions([now(15399)]),
    game_path(Id, '', Path),
    api(Port, get, Path, none, GetStatus, GetErr, _),
    assertion(GetStatus == 404),
    assertion(GetErr.error.code == "game_not_found"),
    act(Port, Id, "reveal", 0-0, ActStatus, ActErr),
    assertion(ActStatus == 404),
    assertion(ActErr.error.code == "game_not_found"),
    create(Port, "medium", Fresh),
    assertion(Fresh.status == "ready").

test(stale_game_isolated_after_new_game,
     [ setup(acceptance_setup(Port)), cleanup(acceptance_cleanup(Port)) ]) :-
    create(Port, "easy", Old),
    create(Port, "easy", New),
    assertion(Old.id \== New.id),
    center(Old, First),
    act_ok(Port, Old.id, "reveal", First, OldAfter),
    assertion(OldAfter.revision == 1),
    assertion(OldAfter.id == Old.id),
    fetch(Port, New.id, NewAfter),
    assertion(NewAfter =@= New),
    assertion(\+ oracle_mines(New.id, _)).

:- end_tests(minesweeper_acceptance).
