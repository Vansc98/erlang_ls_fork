-module(els_beam_mfa).
-include("els_lsp.hrl").
-include_lib("kernel/include/logger.hrl").
-export([add_beam_dir/1]).
-export([update_items/1]).
-export([app_finish_index/0]).
-export([get_all_completion/1]).

-define(SERVER, els_beam_mfa_server).

add_beam_dir(Args) ->
    gen_server:cast(?SERVER, {add_beam_dir, Args}).
update_items(Args) ->
    gen_server:cast(?SERVER, {update_items, Args}).
app_finish_index() ->
    gen_server:cast(?SERVER, app_finish_index).

get_all_completion(Params) ->
    els_beam_mfa_server:get_all_completion(Params).
