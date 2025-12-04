-module(els_beam_mfa).
-include("els_lsp.hrl").
-include_lib("kernel/include/logger.hrl").
-export([init/0, add_beam_dir/1, get_all_completion/1]).
-define(TAB_NAME, ets_beam_mfa).
-record(r_beam_mfa, {
    key = undefined,
    prefix = [],
    % m_chars = [],
    % f_chars = [],
    label = <<>>,
    text = <<>>
}).

init() ->
    ets:new(?TAB_NAME, [named_table, public, set, {keypos, #r_beam_mfa.key}, {read_concurrency, true}]).

add_beam_dir(Dir) ->
    FileFun = fun(File, AccIn) ->
        Mchars = filename:basename(File, ".beam"),
        M = list_to_atom(Mchars),
        case catch M:module_info(exports) of
            FAs when is_list(FAs) ->
                ok;
            _ ->
                FAs = []
        end,
        FAs1 = [{F, A} || {F, A} <- FAs, F =/= module_info],
        Rs = [#r_beam_mfa{key = {M, F, A},
                            prefix = Mchars++":"++atom_to_list(F),
                            % m_chars = [I || I <- Mchars, I=/= $_],
                            % f_chars = [I || I <- atom_to_list(F), I=/= $_],
                        label = unicode:characters_to_binary(io_lib:format("~p:~p/~p", [M, F, A])),
                        text = unicode:characters_to_binary(io_lib:format(format(A), [M, F]))}
                || {F, A} <- FAs, F =/= module_info],
        ets:insert(?TAB_NAME, Rs),
        AccIn
    end,
    spawn(fun() -> filelib:fold_files(Dir, ".*.beam", false, FileFun, []) end).

format(0) -> "~p:~p()";
format(1) -> "~p:~p(${1:_})";
format(2) -> "~p:~p(${1:_}, ${2:_})";
% format(3) -> "~p:~p(${1:_}, ${2:_}, ${3:_})";
% format(4) -> "~p:~p(${1:_}, ${2:_}, ${3:_}, ${4:_})";
% format(5) -> "~p:~p(${1:_}, ${2:_}, ${3:_}, ${4:_}, ${5:_})";
% format(6) -> "~p:~p(${1:_}, ${2:_}, ${3:_}, ${4:_}, ${5:_}, ${6:_})";
format(N) -> "~p:~p(" ++
            [io_lib:format("${~p:_}, ", [I]) || I <- lists:seq(1, N-1)]
            ++ io_lib:format("${~p:_})", [N]).

get_all_completion(PrefixBin) ->
    ?LOG_ERROR("Prefix:~p", [PrefixBin]),
    L = ets:tab2list(?TAB_NAME),
    [r2label(R) || R <- L].

r2label(R) ->
    #{label => R#r_beam_mfa.label,
        kind => ?COMPLETION_ITEM_KIND_TYPE_PARAM,
        insertTextFormat => ?INSERT_TEXT_FORMAT_SNIPPET,
        insertText => R#r_beam_mfa.text
    }.