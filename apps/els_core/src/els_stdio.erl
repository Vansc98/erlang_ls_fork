-module(els_stdio).

-export([
    start_listener/1,
    init/1,
    send/2
]).
-export([loop/4]).
-export([parse_headers/1]).
%%==============================================================================
%% Includes
%%==============================================================================
-include_lib("kernel/include/logger.hrl").

%%==============================================================================
%% els_transport callbacks
%%==============================================================================
-spec start_listener(function()) -> {ok, pid()}.
start_listener(Cb) ->
    IoDevice = application:get_env(els_core, io_device, standard_io),
    % {ok, proc_lib:spawn_link(?MODULE, init, [{Cb, IoDevice}])}.
    {ok, proc_lib:spawn(?MODULE, init, [{Cb, IoDevice}])}.

-spec init({function(), atom() | pid()}) -> no_return().
init({Cb, IoDevice}) ->
    ?LOG_INFO("Starting stdio server... [io_device=~p]", [IoDevice]),
    ok = io:setopts(IoDevice, [binary, {encoding, latin1}]),
    {ok, Server} = application:get_env(els_core, server),
    ok = Server:set_io_device(IoDevice),
    ?MODULE:loop([], IoDevice, Cb, fun json:decode/1).

-spec send(atom() | pid(), binary()) -> ok.
send(IoDevice, Payload) ->
    io:format(IoDevice, "~s", [Payload]).

%%==============================================================================
%% Listener loop function
%%==============================================================================

-spec loop([binary()], any(), function(), fun()) -> no_return().
loop(Lines, IoDevice, Cb, JsonDecoder) ->
    case io:get_line(IoDevice, "") of
        <<"\n">> ->
            try
                Headers = parse_headers(Lines),
                BinLength0 = proplists:get_value(<<"content-length">>, Headers),
                case BinLength0 of
                    undefined ->
                        case Headers of
                            [{_, LenBin}] ->
                                Length = try_parse_len(LenBin);
                            _ ->
                                Length = 1
                        end;
                    BinLength ->
                        Length = binary_to_integer(BinLength)
                end,
                %% Use file:read/2 since it reads bytes
                {ok, Payload} = file:read(IoDevice, Length),
                Request = JsonDecoder(Payload),
                Cb([Request])
            catch
                Class:ExceptionPattern:Stacktrace ->
                    ?LOG_ERROR("Class:~p~nExceptionPattern:~p~nStacktrace:~w~n", [Class, ExceptionPattern, Stacktrace])
            end,
            ?MODULE:loop([], IoDevice, Cb, JsonDecoder);
        eof ->
            Cb([
                #{
                    <<"method">> => <<"exit">>,
                    <<"params">> => []
                }
            ]);
        Line ->
            ?MODULE:loop([Line | Lines], IoDevice, Cb, JsonDecoder)
    end.

-spec parse_headers([binary()]) -> [{binary(), binary()}].
parse_headers(Lines) ->
    [parse_header(Line) || Line <- Lines].

-spec parse_header(binary()) -> {binary(), binary()}.
parse_header(Line) ->
    [Name, Value] = binary:split(Line, <<":">>),
    {string:trim(string:lowercase(Name)), string:trim(Value)}.


try_parse_len(<<>>) ->
	1;
try_parse_len(<<"Content-Length: ", Bin/binary>>) ->
	binary_to_integer(Bin);
try_parse_len(<<_:8, Bin/binary>>) ->
	try_parse_len(Bin).