-module(els_beam_mfa_server).
-behaviour(gen_server).
-include("els_lsp.hrl").
-include_lib("kernel/include/logger.hrl").
%%==============================================================================
%% Macro Definitions
%%==============================================================================
-define(SERVER, ?MODULE).

-define(TAB_DATA, tab_mfa_data).
-define(TAB_JOB,  tab_mfa_job).
-define(TAB_KV,  tab_global_kv).

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
    done_time = 0
}).

%% API
-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([get_all_completion/1]).
-export([set_kv/2]).
-export([get_kv/2]).
-export([not_exclude/2]).
% -export([add_uri/1]).
-record(state, {source_num = 0, 
                all_modules = [], 
                ex = [], 
                save_flag = 0,
                job_flag = false
            }).
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

init(_Args) ->
    ets:new(?TAB_DATA, [named_table, public, set, {keypos, 2}, {read_concurrency, true}]),
    ets:new(?TAB_JOB, [named_table, public, set, {keypos, 2}, {read_concurrency, true}]),
    ets:new(?TAB_KV, [named_table, public, set, {keypos, 1}, {read_concurrency, true}]),
    load(?TAB_DATA),
    load(?TAB_JOB),
    % ?LOG_ERROR("DDD:~p", [DDD]),
    erlang:send(self(), loop),
    {ok, #state{}}.

load(TabName) ->
    TabFile = tab_file(TabName),
    filelib:ensure_dir(TabFile),
    % ?LOG_ERROR("CurrentDir:~p", [CurrentDir]),
    % ?LOG_ERROR("IndexDir:~p", [TabFile]),
    case file:read_file(TabFile) of
        {ok, Bin} ->
            L = binary_to_term(Bin),
            ets:insert(TabName, L);
            % ?LOG_ERROR("dddd:~p", [hd(L)]);
        _ ->
            ok
    end.

save(TabName) ->
    List = ets:tab2list(TabName),
    file:write_file(tab_file(TabName), term_to_binary(List)).

tab_file(TabName) ->
    {ok, CurrentDir} = file:get_cwd(),
    filename:join([CurrentDir, ".vscode/erlang_ls/index/", atom_to_list(TabName)++".bin"]).

set_kv(Key, Value) ->
    ets:insert(?TAB_KV, {Key, Value}).
get_kv(Key, Default) ->
    case ets:lookup(?TAB_KV, Key) of
        [{_, Value}] ->
            Value;
        _ ->
            Default
    end.

handle_call(stop, _From, State) ->
    {stop, normal, stopped, State};

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast({set_exclude_list, Args}, State) ->
    {noreply, State#state{ex = Args}};
handle_cast({add_beam_dir, Args}, State) ->
    add_beam_dir(Args, State#state.ex),
    {noreply, State};
handle_cast({update_items, Args}, State) ->
    update_items(Args),
    {noreply, State};
handle_cast({add_module, M}, State) ->
    case not_exclude(State#state.ex, atom_to_list(M)) of
        true ->
            AllModules = [M|State#state.all_modules],
            NewState = State#state{all_modules = AllModules};
        _ ->
            NewState = State
    end,
    {noreply, NewState};
handle_cast({save}, State) ->
    save(?TAB_DATA),
    save(?TAB_JOB),
    {noreply, State};
handle_cast({update_modules_num, Num}, State) ->
    SaveFlag = State#state.save_flag + Num,
    case SaveFlag > 30 of
        true ->
            save(?TAB_DATA),
            save(?TAB_JOB),
            NewState = State#state{save_flag = 0};
        _ ->
            NewState = State#state{save_flag = SaveFlag}
    end,
    {noreply, NewState};
handle_cast({app_finish_index}, State) ->
    Num = State#state.source_num + 1,
    case Num == length(els_beam_mfa:valid_source()) of
        true ->
            spawn_job(State#state.all_modules);
        false ->
            ok
    end,
    {noreply, State#state{source_num = Num, job_flag = true}};
handle_cast({file_save, Uri}, State) ->
    case State#state.job_flag of
        true ->
            case filename:extension(els_uri:path(Uri)) of
                <<".erl">> ->
                    els_indexing:force_deep_index(Uri),
                    M = els_uri:module(Uri),
                    spawn_job([M]);
                <<".hrl">> ->?LOG_ERROR("save:~p", [Uri]),
                    _Doc = els_indexing:force_deep_index(Uri),
                    % ?LOG_ERROR("Doc:~p", [Doc#{text => <<>>}]),
                    % spawn(fun() -> check_doc(Uri, Doc) end),
                    ok
            end;
        _ ->
            ok
    end,
    {noreply, State};
handle_cast(Msg, State) ->
    ?LOG_ERROR("unkown Msg:~p", [Msg]),
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

add_beam_dir(_Dir, _ExMfaModPre) ->
    ok.
    % FileFun = fun(File, AccIn) ->
    %     Mchars = filename:basename(File, ".beam"),
    %     not_exclude(ExMfaModPre, Mchars) andalso index_beam_module(Mchars),
    %     AccIn
    % end,
    % filelib:is_dir(Dir) andalso spawn(fun() -> filelib:fold_files(Dir, ".*.beam", false, FileFun, []) end).

not_exclude(ExMfaModPre, Mchars) ->
    Pred = fun(ExcludePrefix) ->
        check_prefix(ExcludePrefix, Mchars)
    end,
    not lists:any(Pred, ExMfaModPre).

check_prefix([], _) ->
    true;
check_prefix([Char|T1], [Char|T2]) ->
    check_prefix(T1, T2);
check_prefix(_, _) ->
    false.

update_items(Items) ->
    update_items(Items, other).
update_items(Items, From) ->
    case [update_item(Item) || Item <- Items] of
        [{ok, M}|_] ->
            set_job(#r_job{key = M, done_time = last_modified(M)}),
            From =/= init_job andalso gen_server:cast(?SERVER, {update_modules_num, 1}); 
        _ ->
            ok
    end.

update_item(#{data := #{<<"module">> := M,<<"function">> := F,<<"arity">> := A}, insertText := FaText}) ->
    % ?LOG_ERROR("mfa:~p", [{M, F, A}]),
    R = #r_beam_mfa{key = {M, F, A},
                        prefix = atom_to_list(M)++atom_to_list(F),
                        from = erl_file,
                        fa_label = unicode:characters_to_binary(io_lib:format("~p/~p", [F, A])),
                        mfa_label = unicode:characters_to_binary(io_lib:format("~p:~p/~p", [M, F, A])),
                        fa_text = FaText,
                        mfa_text = unicode:characters_to_binary(io_lib:format("~p:~s", [M, FaText]))},
    ets:insert(?TAB_DATA, R),
    {ok, M};
update_item(Item) ->
    ?LOG_ERROR("Wrong Item:~p", [Item]).

spawn_job(AllModules) ->
    Task = fun(M, {Succeeded0, Skipped0, Failed0}) ->
        {Su, Sk, Fa} = job_process(M),
        {Succeeded0 + Su, Skipped0 + Sk, Failed0 + Fa}
    end,
    Start = erlang:monotonic_time(millisecond),
    Config = #{
        task => Task,
        entries => AllModules,
        title => <<"Indexing MFA">>,
        initial_state => {0, 0, 0},
        on_complete =>
            fun({Succeeded, Skipped, Failed}) ->
                End = erlang:monotonic_time(millisecond),
                Duration = End - Start,
                % Succeeded > 0 andalso gen_server:cast(?SERVER, {update_modules_num, Succeeded}),
                Succeeded > 0 andalso gen_server:cast(?SERVER, {save}),
                Event = #{
                    group => <<"MFA">>,
                    duration_ms => Duration,
                    succeeded => Succeeded,
                    skipped => Skipped,
                    failed => Failed,
                    type => <<"indexing">>
                },
                els_telemetry:send_notification(Event)
            end
    },
    {ok, _Pid} = els_background_job:new(Config),
    ok.

job_process(M) ->
    Now = erlang:system_time(second),
    LM = last_modified(M),
    case get_job(M) of
        [#r_job{done_time = LM}] ->
            {0, 0, 1};
        _ ->
            set_job(#r_job{key = M, done_time = LM}),
            Items = els_completion_provider:exported_definitions(M, function, args),
            % ?LOG_ERROR("Doing Job:~p Items:~p", [M, Items]),
            update_items(Items, init_job),
            case erlang:system_time(second) - Now >= 3 of
                true ->
                    ?LOG_ERROR("job long_time :~p", [M]);
                _ ->
                    ok
            end,
            {1, 0, 0}
    end.

last_modified(M) ->
    case els_utils:find_module(M) of
        {ok, Uri} ->
            FilePath = els_uri:path(Uri),
            filelib:last_modified(FilePath);
        _ ->
            0
    end.

set_job(Job) ->
    ets:insert(?TAB_JOB, Job).
get_job(M) ->
    ets:lookup(?TAB_JOB, M).

loop() ->
    ok.

get_all_completion({EditMod, NameBinary, _Document}) ->
    Prefix = binary_to_list(NameBinary),
    Function = fun(R, {MFAcc, FAcc}) ->
        case check_all_prefix(Prefix, R#r_beam_mfa.prefix) of
            true ->
                MFAcc1 = [mfa_label(R) | MFAcc],
                case R#r_beam_mfa.key of
                    {EditMod, _, _} ->
                        FAcc1 = [fa_label(R)|FAcc];
                    _ ->
                        FAcc1 = FAcc
                end,
                {MFAcc1, FAcc1};
            _ ->
                {MFAcc, FAcc}
        end
    end,
    Result = ets:foldl(Function, {[], []}, ?TAB_DATA),
    % ?LOG_ERROR("Prefix:~p", [{PrefixBin, length(ets:tab2list(?TAB_DATA)), length(MatchL)}]),
    % ?LOG_ERROR("Prefix:~p", [{NameBinary, length(MatchL)}]),
    Result.

check_all_prefix(_, []) ->
    false;
check_all_prefix([], _) ->
    true;
check_all_prefix([Char|T1], [Char|T2]) ->
    check_all_prefix(T1, T2);
check_all_prefix(Prefix, [_|T2]) ->
    check_all_prefix(Prefix, T2).

fa_label(R) ->
    #{label => R#r_beam_mfa.fa_label,
        insertText => R#r_beam_mfa.fa_text,
        detail => <<"Index FA">>,
        documentation => <<"索引函数"/utf8>>,
        kind => ?COMPLETION_ITEM_KIND_FUNCTION,
        insertTextFormat => ?INSERT_TEXT_FORMAT_SNIPPET
    }.
mfa_label(R) ->
    #{label => R#r_beam_mfa.mfa_label,
        insertText => R#r_beam_mfa.mfa_text,
        detail => <<"Index MFA">>,
        documentation => <<"索引函数"/utf8>>,
        kind => ?COMPLETION_ITEM_KIND_FUNCTION,
        insertTextFormat => ?INSERT_TEXT_FORMAT_SNIPPET
    }.
