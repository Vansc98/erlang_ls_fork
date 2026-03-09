-module(els_config_file).
-export([create_config/1]).

create_config(Path) ->
    case filelib:is_file(Path) of
        true ->
            ok;
        false ->
            Text = unicode:characters_to_binary(file_text()),
            filelib:ensure_dir(Path),
            case file:write_file(Path, Text) of
                ok -> ok;
                {error, Reason} -> {error, Reason}
            end
    end.

file_text() ->
<<"
# 以下前缀的模块不会建立索引
exclude_mfa_module_prefix: [gpb, cfg, mcm, proto_check, enif]
"/utf8>>.