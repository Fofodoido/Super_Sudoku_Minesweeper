:- module(server, [start/0, start/1]).
:- encoding(utf8).

/** <module> Servidor HTTP do Campo Minado

Serve `frontend/public` e a API JSON v1:

  POST /api/games
  GET  /api/games/:id
  POST /api/games/:id/actions
*/

:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_json)).
:- use_module(library(http/http_files)).
:- use_module(library(http/http_server_files)).
:- use_module(minesweeper/sessions).

:- prolog_load_context(directory, Dir),
   atom_concat(Dir, '/../frontend/public', Public),
   asserta(user:file_search_path(public, Public)).

:- http_handler(root(api/games), handle_games, [prefix]).
:- http_handler(root(.), serve_static, [prefix]).

serve_static(Request) :-
    http_reply_from_files(public(.), [indexes(['index.html'])], Request), !.
serve_static(Request) :-
    http_404([], Request).

start :- start(8080).

start(Port) :-
    http_server(http_dispatch, [port(Port)]),
    format("Campo Minado em http://localhost:~w~n", [Port]).

:- initialization(run_if_entrypoint, main).

run_if_entrypoint :-
    (   source_file(server:run_if_entrypoint, Source),
        current_prolog_flag(os_argv, OSArgv),
        member(Arg, OSArgv),
        catch(same_file(Arg, Source), _, fail)
    ->  run
    ;   true
    ).

run :-
    current_prolog_flag(argv, Argv),
    ( Argv = [PortAtom|_], atom_number(PortAtom, Port) -> true ; Port = 8080 ),
    start(Port),
    thread_get_message(_).

                 /*******************************
                 *          API HTTP            *
                 *******************************/

handle_games(Request) :-
    catch(dispatch_games(Request), Error, handle_api_exception(Error)).

dispatch_games(Request) :-
    memberchk(method(Method), Request),
    request_path_info(Request, Segments),
    dispatch_games(Method, Segments, Request).

dispatch_games(post, [], Request) :- !,
    ensure_body_size(Request),
    read_json_dict(Request, Body),
    parse_difficulty(Body, Difficulty),
    create_session(Difficulty, Result),
    reply_create_result(Result).
dispatch_games(get, [Id], _Request) :- !,
    get_session(Id, Result),
    reply_session_result(Result).
dispatch_games(post, [Id, actions], Request) :- !,
    ensure_body_size(Request),
    read_json_dict(Request, Action),
    apply_session_action(Id, Action, Result),
    reply_action_result(Result).
dispatch_games(_, Segments, _) :-
    known_games_path(Segments),
    !,
    throw(api_error(405, method_not_allowed,
                    "Método HTTP não permitido para este recurso")).
dispatch_games(_, _, _) :-
    throw(api_error(404, endpoint_not_found, "Endpoint da API não encontrado")).

known_games_path([]).
known_games_path([_]).
known_games_path([_, actions]).

request_path_info(Request, Segments) :-
    ( memberchk(path_info(PathInfo), Request) -> true ; PathInfo = '' ),
    atomic_list_concat(RawSegments, '/', PathInfo),
    exclude(==(''), RawSegments, Segments).

read_json_dict(Request, Dict) :-
    catch(http_read_json(Request, Value,
                         [json_object(dict), value_string_as(string)]),
          Error,
          handle_json_read_error(Error)),
    ( is_dict(Value) -> Dict = Value
    ; throw(api_error(400, invalid_request,
                      "O corpo da requisição deve ser um objeto JSON"))
    ).

ensure_body_size(Request) :-
    (   memberchk(content_length(Length), Request)
    ->  ( Length =< 4096
        -> true
        ;  throw(api_error(413, payload_too_large,
                           "Corpo da requisição excede 4096 bytes"))
        )
    ;   throw(api_error(411, length_required,
                        "Content-Length é obrigatório"))
    ).

handle_json_read_error(error(resource_error(Resource), Context)) :- !,
    throw(error(resource_error(Resource), Context)).
handle_json_read_error(_) :-
    throw(api_error(400, invalid_json, "Corpo JSON inválido")).

parse_difficulty(Body, Difficulty) :-
    ( get_dict(difficulty, Body, Raw), normalize_difficulty(Raw, Difficulty) -> true
    ; throw(api_error(400, invalid_difficulty,
                      "Dificuldade deve ser easy, medium ou hard"))
    ).

normalize_difficulty("easy", easy).
normalize_difficulty("medium", medium).
normalize_difficulty("hard", hard).

reply_create_result(ok(Snapshot)) :-
    reply_json_dict(Snapshot, [status(201), width(0)]).
reply_create_result(error(invalid_difficulty)) :-
    throw(api_error(400, invalid_difficulty,
                    "Dificuldade deve ser easy, medium ou hard")).
reply_create_result(error(session_limit_reached)) :-
    throw(api_error(503, session_limit_reached,
                    "Limite de partidas ativas atingido")).
reply_create_result(Unexpected) :-
    throw(error(unexpected_create_result(Unexpected), _)).

reply_session_result(ok(Snapshot)) :-
    reply_json_dict(Snapshot, [status(200), width(0)]).
reply_session_result(error(session_not_found)) :-
    throw(api_error(404, game_not_found,
                    "Partida não encontrada ou expirada")).
reply_session_result(Unexpected) :-
    throw(error(unexpected_session_result(Unexpected), _)).

reply_action_result(ok(Snapshot)) :-
    reply_json_dict(Snapshot, [status(200), width(0)]).
reply_action_result(error(session_not_found)) :-
    throw(api_error(404, game_not_found,
                    "Partida não encontrada ou expirada")).
reply_action_result(error(invalid_action)) :-
    throw(api_error(400, invalid_action,
                    "Ação deve ser reveal ou toggle_flag")).
reply_action_result(error(invalid_cell)) :-
    throw(api_error(400, invalid_cell,
                    "Coordenadas ausentes, inválidas ou fora do tabuleiro")).
reply_action_result(error(game_over)) :-
    throw(api_error(409, game_over, "A partida já foi encerrada")).
reply_action_result(error(cell_flagged)) :-
    throw(api_error(409, cell_flagged,
                    "Remova a bandeira antes de revelar a célula")).
reply_action_result(error(cell_revealed)) :-
    throw(api_error(409, cell_revealed,
                    "Não é possível marcar uma célula já revelada")).
reply_action_result(Unexpected) :-
    throw(error(unexpected_action_result(Unexpected), _)).

handle_api_exception(api_error(Status, Code, Message)) :- !,
    reply_api_error(Status, Code, Message).
handle_api_exception(Error) :-
    print_message(error, Error),
    reply_api_error(500, internal_error, "Erro interno do servidor").

reply_api_error(Status, Code, Message) :-
    reply_json_dict(_{error: _{code: Code, message: Message}},
                    [status(Status), width(0)]).
