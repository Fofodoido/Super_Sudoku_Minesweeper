:- encoding(utf8).
:- use_module(library(plunit)).
:- use_module(library(thread)).
:- use_module('../minesweeper/sessions').

cell_at(Cells, Row, Col, Cell) :-
    member(Cell, Cells),
    Cell.row =:= Row,
    Cell.col =:= Col,
    !.

session_test_setup :-
    reset_sessions,
    reset_session_config.

session_test_cleanup :-
    reset_sessions,
    reset_session_config.

toggle_once(Id, _) :-
    apply_session_action(Id,
                         _{action: "toggle_flag", row: 0, col: 0},
                         ok(_)).

create_once(_, Result) :- create_session(easy, Result).

successful_creation(ok(_)).
limited_creation(error(session_limit_reached)).

:- begin_tests(minesweeper_sessions).

test(create_all_difficulties,
     [ setup(session_test_setup),
       cleanup(session_test_cleanup),
       forall(member(Difficulty-Rows-Cols-Mines,
                     [easy-9-9-10, medium-16-16-40, hard-16-30-99]))
     ]) :-
    create_session(Difficulty, ok(Snapshot)),
    assertion(atom(Snapshot.id)),
    assertion(Snapshot.difficulty == Difficulty),
    assertion(Snapshot.rows =:= Rows),
    assertion(Snapshot.cols =:= Cols),
    assertion(Snapshot.mineCount =:= Mines),
    assertion(Snapshot.status == ready),
    assertion(Snapshot.revision =:= 0),
    ExpectedCells is Rows * Cols,
    assertion(length(Snapshot.cells, ExpectedCells)).

test(invalid_difficulty,
     [setup(session_test_setup), cleanup(session_test_cleanup)]) :-
    create_session(expert, Result),
    assertion(Result == error(invalid_difficulty)).

test(unique_ids_and_isolation,
     [setup(session_test_setup), cleanup(session_test_cleanup)]) :-
    create_session(easy, ok(A0)),
    create_session(easy, ok(B0)),
    assertion(A0.id \== B0.id),
    apply_session_action(A0.id,
                         _{action: "toggle_flag", row: 0, col: 0},
                         ok(A1)),
    get_session(B0.id, ok(B1)),
    assertion(A1.revision =:= 1),
    assertion(B1.revision =:= 0),
    cell_at(B1.cells, 0, 0, BCell),
    assertion(BCell.state == hidden).

test(expiration_boundary_and_renewal,
     [setup(session_test_setup), cleanup(session_test_cleanup)]) :-
    configure_sessions([ttl_seconds(10), max_sessions(10), now(100)]),
    create_session(easy, ok(Snapshot)),
    Id = Snapshot.id,
    configure_sessions([ttl_seconds(10), max_sessions(10), now(109)]),
    get_session(Id, ok(_)),
    configure_sessions([ttl_seconds(10), max_sessions(10), now(118)]),
    get_session(Id, ok(_)),
    configure_sessions([ttl_seconds(10), max_sessions(10), now(128)]),
    get_session(Id, Missing),
    assertion(Missing == error(session_not_found)),
    get_session(Id, MissingAgain),
    assertion(MissingAgain == error(session_not_found)).

test(rejected_action_renews_activity,
     [setup(session_test_setup), cleanup(session_test_cleanup)]) :-
    configure_sessions([ttl_seconds(10), max_sessions(10), now(100)]),
    create_session(easy, ok(Snapshot)),
    Id = Snapshot.id,
    configure_sessions([ttl_seconds(10), max_sessions(10), now(109)]),
    apply_session_action(Id, _{action: "bogus", row: 0, col: 0}, Error),
    assertion(Error == error(invalid_action)),
    configure_sessions([ttl_seconds(10), max_sessions(10), now(118)]),
    get_session(Id, ok(_)).

test(limit_and_expired_slot_reuse,
     [setup(session_test_setup), cleanup(session_test_cleanup)]) :-
    configure_sessions([ttl_seconds(10), max_sessions(1), now(100)]),
    create_session(easy, ok(First)),
    create_session(easy, LimitError),
    assertion(LimitError == error(session_limit_reached)),
    configure_sessions([ttl_seconds(10), max_sessions(1), now(110)]),
    create_session(medium, ok(Second)),
    assertion(First.id \== Second.id),
    get_session(First.id, Missing),
    assertion(Missing == error(session_not_found)).

test(action_errors_are_preserved,
     [setup(session_test_setup), cleanup(session_test_cleanup)]) :-
    create_session(easy, ok(Snapshot)),
    Id = Snapshot.id,
    apply_session_action(Id, _{action: "reveal", row: -1, col: 0}, Invalid),
    assertion(Invalid == error(invalid_cell)),
    apply_session_action(Id, _{action: "toggle_flag", row: 0, col: 0}, ok(_)),
    apply_session_action(Id, _{action: "reveal", row: 0, col: 0}, Flagged),
    assertion(Flagged == error(cell_flagged)).

test(concurrent_toggles_are_serialized,
     [setup(session_test_setup), cleanup(session_test_cleanup)]) :-
    create_session(easy, ok(Snapshot)),
    Id = Snapshot.id,
    concurrent_maplist(toggle_once(Id), [first, second]),
    get_session(Id, ok(Final)),
    assertion(Final.revision =:= 2),
    cell_at(Final.cells, 0, 0, Cell),
    assertion(Cell.state == hidden).

test(concurrent_creation_respects_limit,
     [setup(session_test_setup), cleanup(session_test_cleanup)]) :-
    configure_sessions([ttl_seconds(7200), max_sessions(2)]),
    concurrent_maplist(create_once, [1, 2, 3, 4, 5], Results),
    include(successful_creation, Results, Created),
    include(limited_creation, Results, Limited),
    assertion(length(Created, 2)),
    assertion(length(Limited, 3)).

:- end_tests(minesweeper_sessions).
