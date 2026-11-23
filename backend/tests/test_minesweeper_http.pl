:- encoding(utf8).
:- use_module(library(plunit)).
:- use_module(library(http/http_client)).
:- use_module(library(json)).
:- use_module(library(http/thread_httpd)).
:- use_module(library(thread)).
:- use_module('../server').
:- use_module('../minesweeper/sessions').

:- prolog_load_context(directory, TestDir),
   directory_file_path(TestDir, 'fixtures/api', FixtureDir),
   asserta(api_fixture_dir(FixtureDir)).

http_test_setup(Port) :-
    reset_sessions,
    reset_session_config,
    server:start(Port).

http_test_cleanup(Port) :-
    http_stop_server(Port, []),
    reset_sessions,
    reset_session_config.

api_url(Port, Path, URL) :-
    format(atom(URL), 'http://127.0.0.1:~w~w', [Port, Path]).

post_json(Port, Path, Body, Status, Reply) :-
    api_url(Port, Path, URL),
    http_post(URL, json(Body), Reply,
              [status_code(Status), json_object(dict)]).

get_json(Port, Path, Status, Reply) :-
    api_url(Port, Path, URL),
    http_get(URL, Reply, [status_code(Status), json_object(dict)]).

post_malformed_json(Port, Path, Status, Reply) :-
    api_url(Port, Path, URL),
    http_post(URL, atom('{'), Reply,
              [ request_header('Content-Type'='application/json'),
                status_code(Status),
                json_object(dict)
              ]).

post_raw_json(Port, Path, Body, Status, Reply) :-
    api_url(Port, Path, URL),
    http_post(URL, atom(Body), Reply,
              [ request_header('Content-Type'='application/json'),
                status_code(Status),
                json_object(dict)
              ]).

create_game(Port, Difficulty, Snapshot) :-
    post_json(Port, '/api/games', _{difficulty: Difficulty}, 201, Snapshot).

game_path(Id, Suffix, Path) :-
    format(atom(Path), '/api/games/~w~w', [Id, Suffix]).

http_toggle(Port, Id, _) :-
    game_path(Id, '/actions', Path),
    post_json(Port, Path,
              _{action: "toggle_flag", row: 0, col: 0},
              200, _).

assert_error(Reply, Code) :-
    assertion(is_dict(Reply.error)),
    assertion(Reply.error.code == Code),
    assertion(string(Reply.error.message)).

assert_active_snapshot_safe(Snapshot) :-
    assertion(memberchk(Snapshot.status, ["ready", "playing"])),
    assertion(\+ get_dict(mines, Snapshot, _)),
    assertion(\+ get_dict(seed, Snapshot, _)),
    forall(member(Cell, Snapshot.cells),
           ( assertion(memberchk(Cell.state, ["hidden", "flagged", "revealed"])),
             assertion(\+ get_dict(mines, Cell, _)),
             assertion(\+ get_dict(seed, Cell, _)),
             ( Cell.state == "revealed"
             -> assertion(integer(Cell.adjacentMines))
             ;  assertion(\+ get_dict(adjacentMines, Cell, _))
             )
           )).

cell_at(Cells, Row, Col, Cell) :-
    member(Cell, Cells), Cell.row =:= Row, Cell.col =:= Col, !.

read_fixture(Name, Dict) :-
    api_fixture_dir(Dir),
    directory_file_path(Dir, Name, Path),
    setup_call_cleanup(open(Path, read, Stream, [encoding(utf8)]),
                       json_read_dict(Stream, Dict),
                       close(Stream)).

has_json_state(State, Cell) :- Cell.state == State.

finish_by_revealing(Port, Id, Index, Final) :-
    Index < 81,
    Row is Index // 9,
    Col is Index mod 9,
    game_path(Id, '/actions', Path),
    post_json(Port, Path,
              _{action: "reveal", row: Row, col: Col}, 200, Snapshot),
    (   memberchk(Snapshot.status, ["won", "lost"])
    ->  Final = Snapshot
    ;   Next is Index + 1,
        finish_by_revealing(Port, Id, Next, Final)
    ).

:- begin_tests(minesweeper_http).

test(create_get_and_action,
     [ setup(http_test_setup(Port)), cleanup(http_test_cleanup(Port)) ]) :-
    create_game(Port, "easy", Created),
    assertion(Created.difficulty == "easy"),
    assertion(Created.status == "ready"),
    assertion(Created.revision =:= 0),
    assertion(length(Created.cells, 81)),
    assert_active_snapshot_safe(Created),
    game_path(Created.id, '', GetPath),
    get_json(Port, GetPath, 200, Loaded),
    assertion(Loaded == Created),
    game_path(Created.id, '/actions', ActionPath),
    post_json(Port, ActionPath,
              _{action: "toggle_flag", row: 0, col: 0},
              200, Flagged),
    assertion(Flagged.revision =:= 1),
    cell_at(Flagged.cells, 0, 0, Cell),
    assertion(Cell.state == "flagged"),
    assert_active_snapshot_safe(Flagged).

test(all_difficulties,
     [ setup(http_test_setup(Port)), cleanup(http_test_cleanup(Port)),
       forall(member(Difficulty-Rows-Cols-Mines,
                     ["easy"-9-9-10, "medium"-16-16-40,
                      "hard"-16-30-99]))
     ]) :-
    create_game(Port, Difficulty, Snapshot),
    assertion(Snapshot.rows =:= Rows),
    assertion(Snapshot.cols =:= Cols),
    assertion(Snapshot.mineCount =:= Mines).

test(validation_errors,
     [ setup(http_test_setup(Port)), cleanup(http_test_cleanup(Port)) ]) :-
    post_json(Port, '/api/games', _{}, 400, MissingDifficulty),
    assert_error(MissingDifficulty, "invalid_difficulty"),
    post_json(Port, '/api/games', [], 400, NotObject),
    assert_error(NotObject, "invalid_request"),
    post_malformed_json(Port, '/api/games', 400, Malformed),
    assert_error(Malformed, "invalid_json"),
    length(LargeChars, 5000),
    maplist(=('x'), LargeChars),
    atom_chars(LargeBody, LargeChars),
    post_raw_json(Port, '/api/games', LargeBody, 413, TooLarge),
    assert_error(TooLarge, "payload_too_large"),
    post_json(Port, '/api/games', _{difficulty: "expert"}, 400, BadDifficulty),
    assert_error(BadDifficulty, "invalid_difficulty"),
    create_game(Port, "easy", Snapshot),
    game_path(Snapshot.id, '/actions', Path),
    post_json(Port, Path, _{action: "hint", row: 0, col: 0}, 400, BadAction),
    assert_error(BadAction, "invalid_action"),
    post_json(Port, Path, _{action: "reveal", row: -1, col: 0}, 400, BadCell),
    assert_error(BadCell, "invalid_cell").

test(not_found_expired_and_method_errors,
     [ setup(http_test_setup(Port)), cleanup(http_test_cleanup(Port)) ]) :-
    get_json(Port, '/api/games/not-a-uuid', 404, Missing),
    assert_error(Missing, "game_not_found"),
    configure_sessions([ttl_seconds(10), max_sessions(10), now(100)]),
    create_game(Port, "easy", Snapshot),
    configure_sessions([ttl_seconds(10), max_sessions(10), now(110)]),
    game_path(Snapshot.id, '', Path),
    get_json(Port, Path, 404, Expired),
    assert_error(Expired, "game_not_found"),
    get_json(Port, '/api/games', 405, WrongMethod),
    assert_error(WrongMethod, "method_not_allowed"),
    get_json(Port, '/api/games/id/unknown', 404, UnknownRoute),
    assert_error(UnknownRoute, "endpoint_not_found").

test(conflicts,
     [ setup(http_test_setup(Port)), cleanup(http_test_cleanup(Port)) ]) :-
    create_game(Port, "easy", Snapshot),
    game_path(Snapshot.id, '/actions', Path),
    post_json(Port, Path,
              _{action: "toggle_flag", row: 0, col: 0}, 200, _),
    post_json(Port, Path,
              _{action: "reveal", row: 0, col: 0}, 409, Flagged),
    assert_error(Flagged, "cell_flagged"),
    post_json(Port, Path,
              _{action: "reveal", row: 1, col: 1}, 200, Revealed),
    post_json(Port, Path,
              _{action: "toggle_flag", row: 1, col: 1}, 409, OpenCell),
    assert_error(OpenCell, "cell_revealed"),
    assertion(Revealed.revision >= 2).

test(game_over_and_validation_precedence,
     [ setup(http_test_setup(Port)), cleanup(http_test_cleanup(Port)) ]) :-
    create_game(Port, "easy", Created),
    finish_by_revealing(Port, Created.id, 0, Final),
    assertion(memberchk(Final.status, ["won", "lost"])),
    game_path(Created.id, '/actions', Path),
    post_json(Port, Path,
              _{action: "toggle_flag", row: 8, col: 8}, 409, Ended),
    assert_error(Ended, "game_over"),
    post_json(Port, Path,
              _{action: "reveal", row: 9, col: 0}, 400, Invalid),
    assert_error(Invalid, "invalid_cell").

test(session_limit,
     [ setup(http_test_setup(Port)), cleanup(http_test_cleanup(Port)) ]) :-
    configure_sessions([ttl_seconds(7200), max_sessions(1)]),
    create_game(Port, "easy", _),
    post_json(Port, '/api/games', _{difficulty: "medium"}, 503, Limited),
    assert_error(Limited, "session_limit_reached").

test(concurrent_actions,
     [ setup(http_test_setup(Port)), cleanup(http_test_cleanup(Port)) ]) :-
    create_game(Port, "easy", Snapshot),
    concurrent_maplist(http_toggle(Port, Snapshot.id), [first, second]),
    game_path(Snapshot.id, '', Path),
    get_json(Port, Path, 200, Final),
    assertion(Final.revision =:= 2),
    cell_at(Final.cells, 0, 0, Cell),
    assertion(Cell.state == "hidden").

test(static_files_still_served,
     [ setup(http_test_setup(Port)), cleanup(http_test_cleanup(Port)) ]) :-
    api_url(Port, '/', URL),
    http_get(URL, Body, [status_code(200), to(string)]),
    assertion(sub_string(Body, _, _, _, "<!doctype html>" )).

test(shared_fixtures_are_valid_json) :-
    Names = ['create-easy.request.json', 'reveal.request.json',
             'toggle-flag.request.json', 'ready-easy.response.json',
             'playing-easy.response.json', 'lost-easy.response.json',
             'invalid-cell.error.json'],
    maplist(read_fixture, Names, Dicts),
    maplist(is_dict, Dicts),
    read_fixture('ready-easy.response.json', Ready),
    assertion(Ready.status == "ready"),
    assertion(length(Ready.cells, 81)),
    assert_active_snapshot_safe(Ready),
    read_fixture('playing-easy.response.json', Playing),
    assertion(Playing.status == "playing"),
    assert_active_snapshot_safe(Playing),
    read_fixture('lost-easy.response.json', Lost),
    assertion(Lost.status == "lost"),
    include(has_json_state("mine"), Lost.cells, Mines),
    assertion(length(Mines, 9)),
    include(has_json_state("exploded"), Lost.cells, Exploded),
    assertion(length(Exploded, 1)).

test(content_length_is_required) :-
    catch(server:ensure_body_size([]), Error, true),
    assertion(Error = api_error(411, length_required, _)).

:- end_tests(minesweeper_http).
