-module(els_beam_mfa).
-export([add_beam_dir/1, get_all_completion/1]).
-define(SERVER, els_beam_mfa_server).

add_beam_dir(Args) ->
    gen_server:cast(?SERVER, {add_beam_dir, Args}).
get_all_completion(PrefixBin) ->
    els_beam_mfa_server:get_all_completion(PrefixBin).
