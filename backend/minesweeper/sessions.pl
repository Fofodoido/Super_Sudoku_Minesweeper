:- module(minesweeper_sessions,
          [ create_session/2,
            get_session/2,
            apply_session_action/3,
            reset_sessions/0,
            configure_sessions/1,
            reset_session_config/0
          ]).
:- encoding(utf8).

/** <module> Sessões em memória para partidas de Campo Minado

Mantém o estado opaco do motor associado a identificadores UUID. Um conjunto
fixo de mutexes particiona as sessões, de forma que ações sobre a mesma partida
são sempre serializadas sem acumular locks ao longo da vida do processo. As
sessões expiram após duas
horas de inatividade por padrão e são perdidas ao reiniciar o processo.

`configure_sessions/1` e `reset_session_config/0` existem para configuração e
testes determinísticos. As opções aceitas são `ttl_seconds/1`,
`max_sessions/1` e `now/1`; omitir `now/1` usa o relógio do sistema.
*/

:- use_module(library(option)).
:- use_module(library(uuid)).
:- use_module(game).

:- dynamic game_session/3.
:- dynamic session_config/3.

default_ttl_seconds(7200).
default_max_sessions(1000).

:- initialization(reset_session_config).

%! create_session(+Difficulty, -Result) is det.
%  Result é ok(Snapshot) ou error(invalid_difficulty/session_limit_reached).
create_session(Difficulty, Result) :-
    (   new_game(Difficulty, Game)
    ->  purge_expired,
        with_mutex(minesweeper_session_registry,
                   create_session_locked(Game, Result))
    ;   Result = error(invalid_difficulty)
    ).

create_session_locked(Game, Result) :-
    session_config(_, MaxSessions, _),
    aggregate_all(count, game_session(_, _, _), Count),
    (   Count >= MaxSessions
    ->  Result = error(session_limit_reached)
    ;   unique_session_id(Id),
        session_now(Now),
        assertz(game_session(Id, Game, Now)),
        public_snapshot(Id, Game, Snapshot),
        Result = ok(Snapshot)
    ).

%! get_session(+Id, -Result) is det.
%  Consultas válidas renovam o instante da última atividade.
get_session(Id, Result) :-
    (   valid_session_id(Id)
    ->  session_mutex(Id, Mutex),
        with_mutex(Mutex, get_session_locked(Id, Result))
    ;   Result = error(session_not_found)
    ).

get_session_locked(Id, Result) :-
    live_session(Id, Game, AccessResult),
    (   AccessResult == ok
    ->  session_now(Now),
        (   replace_session(Id, Game, Now)
        ->  public_snapshot(Id, Game, Snapshot),
            Result = ok(Snapshot)
        ;   Result = error(session_not_found)
        )
    ;   Result = error(session_not_found)
    ).

%! apply_session_action(+Id, +Action, -Result) is det.
%  A leitura, transição e gravação acontecem sob o mutex exclusivo da partida.
apply_session_action(Id, Action, Result) :-
    (   valid_session_id(Id)
    ->  session_mutex(Id, Mutex),
        with_mutex(Mutex, apply_session_action_locked(Id, Action, Result))
    ;   Result = error(session_not_found)
    ).

apply_session_action_locked(Id, Action, Result) :-
    live_session(Id, Game0, AccessResult),
    (   AccessResult == ok
    ->  session_now(Now),
        (   game_action(Game0, Action, ActionResult)
        ->  persist_action_result(ActionResult, Id, Game0, Now, Result)
        ;   throw(error(invalid_game_transition, _))
        )
    ;   Result = error(session_not_found)
    ).

persist_action_result(ok(Game), Id, _Game0, Now, ok(Snapshot)) :-
    replace_session(Id, Game, Now),
    !,
    public_snapshot(Id, Game, Snapshot).
persist_action_result(ok(_), _, _, _, error(session_not_found)).
persist_action_result(error(Reason), Id, Game0, Now, Result) :-
    (   replace_session(Id, Game0, Now)
    ->  Result = error(Reason)
    ;   Result = error(session_not_found)
    ).

% A sessão permanece visível durante a transição, de modo que a contagem para o
% limite nunca observe uma vaga falsa. O mutex por ID impede atualizações
% concorrentes; o mutex do registro protege a substituição curta do fato.
live_session(Id, Game, Result) :-
    with_mutex(minesweeper_session_registry,
               live_session_locked(Id, Game, Result)).

live_session_locked(Id, Game, Result) :-
    (   game_session(Id, StoredGame, LastAccess)
    ->  session_now(Now),
        session_config(TTL, _, _),
        Idle is Now - LastAccess,
        (   Idle >= TTL
        ->  retractall(game_session(Id, _, _)),
            Result = expired
        ;   Game = StoredGame,
            Result = ok
        )
    ;   Result = missing
    ).

replace_session(Id, Game, Now) :-
    with_mutex(minesweeper_session_registry,
               ( retract(game_session(Id, _, _)),
                 assertz(game_session(Id, Game, Now))
               )).

%! reset_sessions is det.
%  Remove todas as partidas em memória. Usado também ao isolar suítes de teste.
reset_sessions :-
    with_mutex(minesweeper_session_registry,
               retractall(game_session(_, _, _))).

%! configure_sessions(+Options) is det.
%  Configura TTL, limite e relógio opcional, preservando defaults omitidos.
configure_sessions(Options) :-
    must_be(list, Options),
    default_ttl_seconds(DefaultTTL),
    default_max_sessions(DefaultMax),
    option(ttl_seconds(TTL), Options, DefaultTTL),
    option(max_sessions(Max), Options, DefaultMax),
    option(now(Now), Options, system),
    validate_config(TTL, Max, Now),
    with_mutex(minesweeper_session_registry,
               ( retractall(session_config(_, _, _)),
                 assertz(session_config(TTL, Max, Now))
               )).

reset_session_config :-
    default_ttl_seconds(TTL),
    default_max_sessions(Max),
    with_mutex(minesweeper_session_registry,
               ( retractall(session_config(_, _, _)),
                 assertz(session_config(TTL, Max, system))
               )).

validate_config(TTL, Max, Now) :-
    must_be(number, TTL),
    ( TTL > 0 -> true ; domain_error(positive_number, TTL) ),
    must_be(integer, Max),
    ( Max > 0 -> true ; domain_error(positive_integer, Max) ),
    ( Now == system -> true ; must_be(number, Now) ).

session_now(Now) :-
    session_config(_, _, ConfiguredNow),
    (   ConfiguredNow == system
    ->  get_time(Now)
    ;   Now = ConfiguredNow
    ).

unique_session_id(Id) :-
    repeat,
    uuid(Id, [version(4)]),
    \+ game_session(Id, _, _),
    !.

valid_session_id(Id) :-
    atom(Id),
    atomic_list_concat(Parts, '-', Id),
    maplist(atom_length, Parts, [8, 4, 4, 4, 12]),
    maplist(hex_atom, Parts).

hex_atom(Atom) :-
    atom_codes(Atom, Codes),
    maplist(hex_code, Codes).

hex_code(Code) :-
    (   code_type(Code, digit)
    ;   between(0'a, 0'f, Code)
    ;   between(0'A, 0'F, Code)
    ).

session_mutex(Id, Mutex) :-
    (   atomic(Id)
    ->  term_hash(Id, Hash),
        Stripe is Hash mod 256,
        format(atom(Mutex), 'minesweeper_session_stripe_~d', [Stripe])
    ;   Mutex = minesweeper_invalid_session
    ).

purge_expired :-
    with_mutex(minesweeper_session_registry,
               findall(Id, game_session(Id, _, _), Ids)),
    maplist(purge_session_if_expired, Ids).

purge_session_if_expired(Id) :-
    session_mutex(Id, Mutex),
    with_mutex(Mutex, purge_session_if_expired_locked(Id)).

purge_session_if_expired_locked(Id) :-
    with_mutex(minesweeper_session_registry,
               purge_session_if_expired_registry_locked(Id)).

purge_session_if_expired_registry_locked(Id) :-
    ( game_session(Id, _, LastAccess), session_now(Now),
      session_config(TTL, _, _), Now - LastAccess >= TTL
    -> retractall(game_session(Id, _, _))
    ;  true
    ).
