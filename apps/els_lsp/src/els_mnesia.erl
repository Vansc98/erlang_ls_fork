-module(els_mnesia).
-behaviour(gen_server).
-include("els_lsp.hrl").
-define(SERVER, ?MODULE).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
%% API
-export([start_distribution/0]).
-export([call/1, cast/1]).
-export([set_val/2, set_val/3, get_val/1, get_val/2]).
-export([dir/0]).
-export([get_lastest_docment/2]).
-export([hook_deep_index/3]).
-export([completion/1]).
-export([hook_file_save/1]).
-export([get_uri/1]).
-record(state, {
}).

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

init(_Args) ->
    put(server_flag, ?SERVER),
    ets:new(?ETS_KV, [named_table, public, set, {keypos, 2}, {read_concurrency, true}]),
    {ok, #state{}}.
is_server() ->
    get(server_flag) == ?SERVER.
dir() ->
    {ok, CurrentDir} = file:get_cwd(),
    Dir = filename:join([CurrentDir, ".erlang_ls/mnesia", integer_to_list(els_distribution_server:node_int())]),
    filelib:ensure_dir(Dir++"/a"),
    Dir.

set_val(Key, Value) ->
    set_val(Key, Value, false).
set_val(Key, Value, _IsMnesia = true) ->
    catch mnesia:dirty_write(r_kv, #r_kv{key = Key, value = Value});
set_val(Key, Value, _IsMnesia = false) ->
    ets:insert(?ETS_KV, #r_kv{key = Key, value = Value}).
get_val(Key) ->
    get_val(Key, false).
get_val(Key, _IsMnesia = true) ->
    case catch mnesia:dirty_read(r_kv, Key) of
        [#r_kv{value = Value}] ->
            Value;
        _ ->
            undefined
    end;
get_val(Key, _IsMnesia = false) ->
    case ets:lookup(?ETS_KV, Key) of
        [#r_kv{value = Value}] ->
            Value;
        [] ->
            undefined
    end.

get_uri(Uri) when is_binary(Uri) ->
    mnesia:dirty_read(r_uri, Uri);
get_uri(M) when is_atom(M) ->
    mnesia:dirty_select(r_uri, [{#r_uri{basename = M, _ = '_'}, [], ['$_']}]).

handle_call(stop, _From, State) ->
    {stop, normal, stopped, State};
handle_call(Request, _From, State) ->
    {reply, handle(Request), State}.
handle_cast(Msg, State) ->
    handle(Msg),
    {noreply, State}.
handle_info(loop, State) ->
    % erlang:send_after(1000, self(), loop),
    {noreply, State};
handle_info(Info, State) ->
    handle(Info),
    {noreply, State}.
terminate(_Reason, _State) ->
    ok.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

handle(Func) when is_function(Func) ->
    try
        Func()
    catch
        Class:ExceptionPattern:Stacktrace ->
            ?LOG_ERROR("C:~p~nE:~p~nS:~p", [Class, ExceptionPattern, Stacktrace])
    end;
handle(Request) ->
    ?LOG_ERROR("unkown Msg:~p", [Request]),
    ok.

call(Msg) ->
    gen_server:call(?SERVER, Msg).
cast(Msg) ->
    gen_server:cast(?SERVER, Msg).

start_distribution() ->
    case is_server() of
        true ->
            application:set_env(mnesia, dir, dir()),
            mnesia:system_info(use_dir) == false andalso mnesia:create_schema([node()]),
            case mnesia:start() of
                ok ->
                    mnesia:create_table(r_uri, [{attributes, record_info(fields, r_uri)}, {disc_copies, [node()]}]),
                    mnesia:create_table(r_kv, [{attributes, record_info(fields, r_kv)}, {disc_copies, [node()]}]),
                    mnesia:wait_for_tables(mnesia:system_info(tables), 5000),
                    ok;
                {error, Reason} ->
                    ?LOG_ERROR("mnesia start failed: ~p", [Reason])
            end;
        false ->
            call(fun start_distribution/0)
    end.

get_lastest_docment(Uri, LastModified) ->
    case mnesia:dirty_read(r_uri, Uri) of
        [#r_uri{last_modified = LastModified, version = ?MNESIA_VERSION}] ->
            true;
        _ ->
            false
    end.
hook_deep_index(Uri, LastModified, Document) ->
    POIs = els_dt_document:pois(Document, [record_def_field]),
    Records = index_records(POIs, undefined, [], #{}),
    Defines0 = els_dt_document:pois(Document, [define]),
    Defines = [DefineName || #{id := DefineName} <- Defines0],
    case filename:extension(Uri) of
        <<".erl">> ->
            FaItems = els_completion_provider:definitions(Document, function, args, true),
            M = els_uri:module(Uri),
            MChars = atom_to_list(M),
            Ruri = #r_uri{
                            uri = Uri,
                            type = erl,
                            last_modified = LastModified,
                            basename = M,
                            records = Records,
                            defines = Defines,
                            fa_list = [item2rfa(I) || I <- FaItems],
                            prefix = MChars
                        },
            mnesia:dirty_write(r_uri, Ruri);
        <<".hrl">> ->
            Ruri = #r_uri{
                            uri = Uri,
                            type = hrl,
                            last_modified = LastModified,
                            basename = filename:basename(Uri),
                            records = Records,
                            defines = Defines
                        },
            mnesia:dirty_write(r_uri, Ruri);
        _ ->
            ok
    end.

index_records([], undefined, _Fields, Records) ->
    Records;
index_records([], RecordName0, Fields, Records) ->
    Records#{RecordName0 => lists:reverse(Fields)};
index_records([#{id := {RecordName, FieldName}}|T], undefined, _Fields, Records) ->
    index_records(T, RecordName, [FieldName], Records);
index_records([#{id := {RecordName, FieldName}}|T], RecordName0, Fields, Records) ->
    case RecordName == RecordName0 of
        true ->
            Fields1 = [FieldName|Fields],
            index_records(T, RecordName, Fields1, Records);
        false ->
            index_records(T, RecordName, [FieldName], Records#{RecordName0 => lists:reverse(Fields)})
    end.

item2rfa(#{data := #{<<"module">> := M,<<"function">> := F,<<"arity">> := A}, insertText := FaText}) ->
    % ?V(binary_to_list(FaText)),
    #r_fa{
        prefix = atom_to_list(F),
        documentation = unicode:characters_to_binary(mfa_detail(binary_to_list(FaText), [])),
        fa_label = unicode:characters_to_binary(io_lib:format("~p/~p", [F, A])),
        mfa_label = unicode:characters_to_binary(io_lib:format("~p:~p/~p", [M, F, A])),
        fa_text = FaText,
        mfa_text = unicode:characters_to_binary(io_lib:format("~p:~s", [M, FaText]))
    }.

hook_file_save(Uri0) ->
    Config = #{
        task => fun(Uri, _State) ->
            LastModified = els_uri:last_modified(Uri),
            case mnesia:dirty_read(r_uri, Uri) of
                [#r_uri{last_modified = LastModified}] ->
                    ok;
                _ ->
                    Document = els_indexing:force_deep_index(Uri),
                    hook_deep_index(Uri, LastModified, Document)
            end
        end,
        entries => [Uri0],
        title => <<"Indexing ", Uri0/binary>>
    },
    els_background_job:new(Config).

mfa_detail([$$, ${, _, $:|T], Detail) ->
    mfa_detail(T, Detail);
mfa_detail([$}|T], Detail) ->
    mfa_detail(T, Detail);
mfa_detail([H|T], Detail) ->
    mfa_detail(T, [H|Detail]);
mfa_detail([], Detail) ->
    lists:reverse(Detail).

completion({code_action, add_include_file, {_Uri, _Range, Kind, Name, _Id}}) ->
    case Kind of
        record ->
            Function = fun(R, Acc) ->
                case R#r_uri.type of
                    hrl ->
                        case maps:get(Name, R#r_uri.records, undefined) of
                            undefined ->
                                Acc;
                            _ ->
                                [R#r_uri.basename| Acc]
                        end;
                    _ ->
                        Acc
                end
            end;
        define ->
            Function = fun(R, Acc) ->
                case R#r_uri.type of
                    hrl ->
                        case lists:member(Name, R#r_uri.defines) of
                            false ->
                                Acc;
                            _ ->
                                [R#r_uri.basename| Acc]
                        end;
                    _ ->
                        Acc
                end
            end;
        _ ->
            Function = fun(_R, _Acc) -> [] end
    end,
    ets:foldl(Function, [], r_uri);
completion({hrl_file}) ->
    Function = fun(R, Acc) ->
        case R#r_uri.type of
            hrl ->
                [els_completion_provider:item_kind_file(R#r_uri.basename)|Acc];
            _ ->
                Acc
        end
    end,
    ets:foldl(Function, [], r_uri);
completion({function, args, EditMod, NameBinary, _Document, _Line}) ->
    Prefix = binary_to_list(NameBinary),
    Function = fun(R, {MFAcc, FAcc}) ->
        case R#r_uri.type of
            erl ->
                case match_prefix(Prefix, R#r_uri.prefix) of
                    true ->
                        case R#r_uri.basename of
                            EditMod ->
                                FAcc1 = fa_label(R)++FAcc;
                            _ ->
                                FAcc1 = FAcc
                        end,
                        {mfa_label(R, []) ++ MFAcc, FAcc1};
                    RemainPrefix ->
                        {mfa_label(R, RemainPrefix) ++ MFAcc, FAcc}
                end;
            _ ->
                {MFAcc, FAcc}
        end
    end,
    {MFAItems, FAITems} = ets:foldl(Function, {[], []}, r_uri),
    % {MFAItems, FAITems} = mnesia:foldl(Function, {[], []}, r_uri),
    % ?V({POIKind, ItemFormat, EditMod, NameBinary, length(MFAItems)}),
    {mfa, MFAItems, FAITems};
completion({any, args, _EditMod, _NameBinary, Document, Line}) ->
    L = els_completion_provider:attributes(Document, Line),
    [case maps:get(label, Item, undefined) of
        <<$-, _/binary>> ->
            InsertText = maps:get(insertText, Item, <<>>),
            Item#{insertText => <<$-,InsertText/binary>>};
        _ ->
            Item
    end
    || Item <- L];
completion({POIKind, ItemFormat, _EditMod, _NameBinary, _Document}) ->
    ?V({POIKind, ItemFormat}),
    [];
completion(Msg) ->
    ?V(Msg),
    [].

mfa_label(R, RemainPrefix) ->
    [#{label => FA#r_fa.mfa_label,
        insertText => FA#r_fa.mfa_text,
        % detail => <<"Index MFA">>,
        % documentation => FA#r_fa.documentation,
        documentation => #{kind => <<"markdown">>,
                        value => <<"```erlang\n", (FA#r_fa.documentation)/binary, "\n```">>
                        },
        kind => ?COMPLETION_ITEM_KIND_FUNCTION,
        insertTextFormat => ?INSERT_TEXT_FORMAT_SNIPPET
    }|| FA <- R#r_uri.fa_list, match_prefix(RemainPrefix, FA#r_fa.prefix) == true].
fa_label(R) ->
    [#{label => FA#r_fa.mfa_label,
        insertText => FA#r_fa.fa_text,
        % documentation => FA#r_fa.documentation,
        documentation => #{kind => <<"markdown">>,
                        value => <<"```erlang\n", (FA#r_fa.documentation)/binary, "\n```">>
                        },
        kind => ?COMPLETION_ITEM_KIND_FUNCTION,
        insertTextFormat => ?INSERT_TEXT_FORMAT_SNIPPET
    }|| FA <- R#r_uri.fa_list].

match_prefix([], _) ->
    true;
match_prefix([Char|T1], [Char|T2]) ->
    match_prefix(T1, T2);
match_prefix([Char|T1], [_|T2]) ->
    match_prefix([Char|T1], T2);
match_prefix(RemainPrefix, _) ->
    RemainPrefix.