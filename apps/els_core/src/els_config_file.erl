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
exclude_module_prefix: [gpb, cfg, mcm, proto_check, enif]

# 是否补全函数变量名(修改此选项需要删除mnesia目录,重新建立索引)
var_name_completion: true

# 鼠标悬停时查看function的完整实现
hover_function_detail: true

# 允许代码格式化
document_formatting: false
"/utf8>>.