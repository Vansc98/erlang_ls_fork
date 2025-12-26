-module(els_mnesia).

%% API
-export([start/0, init/0, stop/0]).
-export([create_table/2, 
         insert/2, 
         lookup/2, 
         delete/2, 
         delete_table/1, 
         all/1,
         update/3,
         transaction/1,
         wait_for_tables/0]).
-export([dir/0]).

%% 初始化 Mnesia 数据库
init() ->
    application:set_env(mnesia, dir, dir()),
    case mnesia:start() of
        ok ->
            create_schema_if_not_exists(),
            wait_for_tables(),
            ok;
        {error, Reason} ->
            {error, Reason}
    end.

dir() ->
    {ok, CurrentDir} = file:get_cwd(),
    Dir = filename:join([CurrentDir, ".vscode/erlang_ls/mnesia"]),
    Dir.

%% 启动 Mnesia 服务
start() ->
    mnesia:start().

%% 停止 Mnesia 服务
stop() ->
    mnesia:stop().

%% 创建表
-spec create_table(atom(), list()) -> ok | {error, term()}.
create_table(Name, Opts) ->
    case mnesia:create_table(Name, Opts) of
        {atomic, ok} ->
            ok;
        {aborted, Reason} ->
            {error, Reason}
    end.

%% 插入数据
-spec insert(atom(), tuple()) -> ok | {error, term()}.
insert(_Table, Record) ->
    F = fun() ->
            mnesia:write(Record)
        end,
    case mnesia:transaction(F) of
        {atomic, ok} ->
            ok;
        {aborted, Reason} ->
            {error, Reason}
    end.

%% 查找数据
-spec lookup(atom(), term()) -> {ok, list()} | {error, term()}.
lookup(Table, Key) ->
    F = fun() ->
            mnesia:read(Table, Key)
        end,
    case mnesia:transaction(F) of
        {atomic, Result} ->
            {ok, Result};
        {aborted, Reason} ->
            {error, Reason}
    end.

%% 更新数据
-spec update(atom(), term(), term()) -> ok | {error, term()}.
update(Table, Key, NewRecord) ->
    F = fun() ->
            case mnesia:read(Table, Key) of
                [] ->
                    mnesia:write(NewRecord);
                _ ->
                    mnesia:delete({Table, Key}),
                    mnesia:write(NewRecord)
            end
        end,
    case mnesia:transaction(F) of
        {atomic, ok} ->
            ok;
        {aborted, Reason} ->
            {error, Reason}
    end.

%% 删除记录
-spec delete(atom(), term()) -> ok | {error, term()}.
delete(Table, Key) ->
    F = fun() ->
            mnesia:delete({Table, Key})
        end,
    case mnesia:transaction(F) of
        {atomic, ok} ->
            ok;
        {aborted, Reason} ->
            {error, Reason}
    end.

%% 删除表
-spec delete_table(atom()) -> ok | {error, term()}.
delete_table(Table) ->
    case mnesia:delete_table(Table) of
        {atomic, ok} ->
            ok;
        {aborted, Reason} ->
            {error, Reason}
    end.

%% 获取表中所有记录
-spec all(atom()) -> {ok, list()} | {error, term()}.
all(Table) ->
    F = fun() ->
            mnesia:match_object({Table, '_'})
        end,
    case mnesia:transaction(F) of
        {atomic, Result} ->
            {ok, Result};
        {aborted, Reason} ->
            {error, Reason}
    end.

%% 执行事务
-spec transaction(fun()) -> {atomic, term()} | {aborted, term()}.
transaction(Fun) ->
    mnesia:transaction(Fun).

%% 等待所有表准备就绪
wait_for_tables() ->
    mnesia:wait_for_tables(mnesia:system_info(tables), 5000).

%% 内部函数：创建 schema（如果不存在）
create_schema_if_not_exists() ->
    case mnesia:system_info(use_dir) of
        false ->
            % 如果没有使用目录，则创建 schema
            mnesia:create_schema([node()]);
        true ->
            % 已经存在 schema，无需创建
            ok
    end.