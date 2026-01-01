-ifndef(__ELS_LSP_HRL__).
-define(__ELS_LSP_HRL__, 1).

-include_lib("els_core/include/els_core.hrl").
-include_lib("kernel/include/logger.hrl").
-define(APP, els_lsp).

-define(LSP_LOG_FORMAT, [
    "[", time, "] ", "[", level, "] ", msg, " [", mfa, " line:", line, "] ", pid, "\n"
]).
-define(MNESIA_VERSION, 1).
-define(V(Var), ?LOG_ERROR("~p=~p", [??Var, Var])).
-record(r_uri, {
    uri = <<>>,
    version = ?MNESIA_VERSION,
    type = undefined, %% erl|hrl
    last_modified = undefined,
    deep_index = #{},
    deep_index_time = undefined,
    basename = undefined,
    prefix = "",
    fa_list = [] %% r_fa
}).
-record(r_fa, {
    fa = {f, 0},
    prefix = "",
    documentation = <<>>,
    fa_label = <<>>,
    fa_text = <<>>,
    mfa_label = <<>>,
    mfa_text = <<>>
}).
-define(ETS_KV, ets_kv).
-record(r_kv, {
    key = undefined,
    value = undefined
}).
-endif.
