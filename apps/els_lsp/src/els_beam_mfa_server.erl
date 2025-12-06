-module(els_beam_mfa_server).
-behaviour(gen_server).
-include("els_lsp.hrl").
-include_lib("kernel/include/logger.hrl").
%%==============================================================================
%% Macro Definitions
%%==============================================================================
-define(SERVER, ?MODULE).

-define(TAB_NAME, tab_beam_mfa).
-define(TAB_JOB, tab_todo_uri).

-record(r_beam_mfa, {
    key = undefined, %% {m, f, a}
    prefix = [],
    % m_chars = [],
    % f_chars = [],
    fa_label = <<>>,
    fa_text = <<>>,
    mfa_label = <<>>,
    mfa_text = <<>>,
    from = undefined
}).

-record(r_job, {
    key = undefined,
    type = undefined
}).

%% API
-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([get_all_completion/1]).
% -export([add_uri/1]).
-record(state, {dummy}).
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

init(_Args) ->
    ets:new(?TAB_NAME, [named_table, public, set, {keypos, 2}, {read_concurrency, true}]),
    ets:new(?TAB_JOB, [named_table, public, set, {keypos, 2}, {read_concurrency, true}]),
    erlang:send(self(), loop),
    {ok, #state{dummy=1}}.

handle_call(stop, _From, State) ->
    {stop, normal, stopped, State};

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast({add_beam_dir, Args}, State) ->
    add_beam_dir(Args),
    {noreply, State};
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(loop, State) ->
    erlang:send_after(500, self(), loop),
    loop(),
    {noreply, State};
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

add_beam_dir({Dir, ExMfaModPre}) ->
    FileFun = fun(File, AccIn) ->
        Mchars = filename:basename(File, ".beam"),
        Pred = fun(ExcludePrefix) ->
            check_prefix(ExcludePrefix, Mchars)
        end,
        not lists:any(Pred, ExMfaModPre) andalso index_module(Mchars),
        AccIn
    end,
    filelib:is_dir(Dir) andalso spawn(fun() -> filelib:fold_files(Dir, ".*.beam", false, FileFun, []) end),
    ok.

index_module(Mchars) ->
    M = list_to_atom(Mchars),
    case catch M:module_info(exports) of
        FAs when is_list(FAs) ->
            [case ets:lookup(?TAB_NAME, {M, F, A}) of
                [] -> 
                    add_job(#r_job{key = M, type = mfa}),
                    R = #r_beam_mfa{key = {M, F, A},
                        prefix = Mchars++atom_to_list(F),
                        from = beam_dir,
                        fa_label = unicode:characters_to_binary(io_lib:format("~p/~p", [F, A])),
                        mfa_label = unicode:characters_to_binary(io_lib:format("~p:~p/~p", [M, F, A])),
                        fa_text = unicode:characters_to_binary(io_lib:format(format(A), [F])),
                        mfa_text = unicode:characters_to_binary(io_lib:format("~p:" ++ format(A), [M, F]))},
                    ets:insert(?TAB_NAME, R);
                _ ->
                    ok
            end
            || {F, A} <- FAs, F =/= module_info];
        _ ->
            ok
    end.

add_job(Job) ->
    ets:insert(?TAB_JOB, Job).

loop() ->
    ok.
%     case ets:first(?TAB_JOB) of
%         '$end_of_table' ->
%             ignore;
%         Key ->
%             [Job] = ets:lookup(?TAB_JOB, Key),
%             do_job(Job)
%     end.

% do_job(Job) ->
%     case Job#r_job.type of
%         mfa ->
%             Module = Job#r_job.key,
%             Items = els_completion_provider:exported_definitions(Module, function, args),
%             update_item(Items);
%         _ ->
%             ok
%     end.

% update_item(Item) ->
%     #{data := Data, insertText := Text} = maps:get(data, Item, #{}),
%     #{
%         <<"module">> := M,
%         <<"type">> := F,
%         <<"arity">> := A
%     } = Data,
%     [R] = ets:lookup(?TAB_NAME, {M, F, A}),
%     NewText = unicode:characters_to_binary(io_lib:format("~p:~p", [M, Text])),
%     NewR = R#r_beam_mfa{text = NewText},
%     ?LOG_ERROR("update:~p", [M]),
%     ets:insert(?TAB_NAME, NewR).

format(0) -> "~p()";
format(1) -> "~p(${1:_})";
format(2) -> "~p(${1:_}, ${2:_})";
format(3) -> "~p(${1:_}, ${2:_}, ${3:_})";
format(4) -> "~p(${1:_}, ${2:_}, ${3:_}, ${4:_})";
format(5) -> "~p(${1:_}, ${2:_}, ${3:_}, ${4:_}, ${5:_})";
format(6) -> "~p(${1:_}, ${2:_}, ${3:_}, ${4:_}, ${5:_}, ${6:_})";
format(N) -> "~p(" ++
            [io_lib:format("${~p:_}, ", [I]) || I <- lists:seq(1, N-1)]
            ++ io_lib:format("${~p:_})", [N]).

get_all_completion({EditMod, NameBinary, _Document}) ->
    Prefix = binary_to_list(NameBinary),
    % L = ets:tab2list(?TAB_NAME),
    % MatchL = [r2label(R) || R <- L, check_prefix(Prefix, R#r_beam_mfa.prefix)],
    Function = fun(R, Acc) ->
        case check_prefix(Prefix, R#r_beam_mfa.prefix) of
            true ->
                case R#r_beam_mfa.key of
                    {EditMod, _, _} ->
                        [fa_label(R), mfa_label(R) | Acc];
                    _ ->
                        [mfa_label(R) | Acc]
                end;
            _ ->
                Acc
        end
    end,
    MatchL = ets:foldl(Function, [], ?TAB_NAME),
    % ?LOG_ERROR("Prefix:~p", [{PrefixBin, length(ets:tab2list(?TAB_NAME)), length(MatchL)}]),
    ?LOG_ERROR("Prefix:~p", [{NameBinary, length(MatchL)}]),
    MatchL.

check_prefix(_, []) ->
    false;
check_prefix([], _) ->
    true;
check_prefix([Char|T1], [Char|T2]) ->
    check_prefix(T1, T2);
check_prefix(Prefix, [_|T2]) ->
    check_prefix(Prefix, T2).

fa_label(R) ->
    #{label => R#r_beam_mfa.fa_label,
        insertText => R#r_beam_mfa.fa_text,
        detail => <<"Beam FA">>,
        documentation => <<"beam文件导出的函数"/utf8>>,
        kind => ?COMPLETION_ITEM_KIND_FUNCTION,
        insertTextFormat => ?INSERT_TEXT_FORMAT_SNIPPET
    }.
mfa_label(R) ->
    #{label => R#r_beam_mfa.mfa_label,
        insertText => R#r_beam_mfa.mfa_text,
        detail => <<"Beam MFA">>,
        documentation => <<"beam文件导出的函数"/utf8>>,
        kind => ?COMPLETION_ITEM_KIND_FUNCTION,
        insertTextFormat => ?INSERT_TEXT_FORMAT_SNIPPET
    }.