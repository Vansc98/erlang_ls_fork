-module(els_beam_mfa).
-include("els_lsp.hrl").
-include_lib("kernel/include/logger.hrl").
-export([set_exclude_list/1]).
-export([add_beam_dir/1]).
-export([update_items/1]).
-export([app_finish_index/1]).
-export([get_all_completion/1]).
-export([valid_source/0]).
-export([mark_index/1]).
-export([check_module/2]).

-define(SERVER, els_beam_mfa_server).

set_exclude_list(Args) ->
    gen_server:cast(?SERVER, {set_exclude_list, Args}).
add_beam_dir(Args) ->
    gen_server:cast(?SERVER, {add_beam_dir, Args}).
update_items(Args) ->
    gen_server:cast(?SERVER, {update_items, Args}).


get_all_completion(Params) ->
    els_beam_mfa_server:get_all_completion(Params).


% ============================================================================
% background job
% ============================================================================
valid_source() ->
    [app, dep].

get_all_modules() ->
    get({?MODULE, all_modules}).
set_all_modules(L) ->
    put({?MODULE, all_modules}, L).

mark_index(Source) ->
    lists:member(Source, valid_source()) andalso set_all_modules([]).

check_module(module, M) ->
    case get_all_modules() of
        L when is_list(L) ->
            gen_server:cast(?SERVER, {add_module, M});
        _ ->
            ok
    end;
check_module(_Kind, _ID) ->
    ok.

app_finish_index(Source) ->
    lists:member(Source, valid_source()) andalso gen_server:cast(?SERVER, {app_finish_index}).