%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 1997-2013. All Rights Reserved.
%%
%% The contents of this file are subject to the Erlang Public License,
%% Version 1.1, (the "License"); you may not use this file except in
%% compliance with the License. You should have received a copy of the
%% Erlang Public License along with this software. If not, it can be
%% retrieved online at http://www.erlang.org/.
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and limitations
%% under the License.
%%
%% %CopyrightEnd%
%%

% ripped from OTP. we reimplement gen_tcp:connect to filter ip addresses returned from the resolver

-module(lhttpc_filtered_sock).

-export([connect/4, close/1, send/2, recv/2, recv/3, shutdown/2, controlling_process/2,

setopts/2,
getopts/2,
peername/1,
sockname/1,
port/1
  ]).

connect(Address, Port, Opts, Time) ->
    Timer = inet:start_timer(Time),
    Res = (catch connect1(Address,Port,Opts,Timer)),
    _ = inet:stop_timer(Timer),
    case Res of
        {ok,S} -> {ok,S};
        {error, einval} -> exit(badarg);
        {'EXIT',Reason} -> exit(Reason);
        Error ->  Error
    end.

connect1(Address,Port,Opts,Timer) ->
    Mod = mod(Opts, Address),
    case Mod:getaddrs(Address,Timer) of
        {ok,IPs} ->
            case Mod:getserv(Port) of
                {ok,TP} ->
                  Filter = lists:keyfind(ip_filter, 1, Opts),
                  Opts1 = lists:keydelete(ip_filter, 1, Opts),
                  try_connect(IPs,Filter,TP,Opts1,Timer,Mod,{error,einval});
                Error -> Error
            end;
        Error -> Error
    end.

try_connect([IP|IPs], Filter,Port, Opts, Timer, Mod, _Err) ->
    Time = inet:timeout(Timer),
    case do_connect(Mod, Filter, IP, Port, Opts, Time) of
        {ok,S} -> {ok,S};
        {error,einval} -> {error, einval};
        {error,timeout} -> {error,timeout};
        Err1 -> try_connect(IPs, Filter,Port, Opts, Timer, Mod, Err1)
    end;
try_connect([], _Filter, _Port, _Opts, _Timer, _Mod, Err) ->
    Err.

do_connect(Mod, {ip_filter, Filter}, IP, Port, Opts, Time) ->
  case Filter(IP) of
    true ->
      Mod:connect(IP, Port, Opts, Time);
    false ->
      {error, invalid_ip}
  end;
do_connect(Mod, _Filter, IP, Port, Opts, Time) ->
  Mod:connect(IP, Port, Opts, Time).


mod(Address) ->
    case inet_db:tcp_module() of
        inet_tcp when tuple_size(Address) =:= 8 ->
            inet6_tcp;
        Mod ->
            Mod
    end.

%% Get the tcp_module, but option tcp_module|inet|inet6 overrides
mod([{tcp_module,Mod}|_], _Address) ->
    Mod;
mod([inet|_], _Address) ->
    inet_tcp;
mod([inet6|_], _Address) ->
    inet6_tcp;
mod([{ip, Address}|Opts], _) ->
    mod(Opts, Address);
mod([{ifaddr, Address}|Opts], _) ->
    mod(Opts, Address);
mod([_|Opts], Address) ->
    mod(Opts, Address);
mod([], Address) ->
    mod(Address).

close(Socket) -> gen_tcp:close(Socket).

send(Socket, Data) -> gen_tcp:send(Socket, Data).

recv(Socket, Length) -> gen_tcp:recv(Socket, Length).
recv(Socket, Length, Timeout) -> gen_tcp:recv(Socket, Length, Timeout).

shutdown(Socket, How) -> gen_tcp:shutdown(Socket, How).

controlling_process(Socket, Owner) -> gen_tcp:controlling_process(Socket, Owner).


setopts(A1, A2) -> inet:setopts(A1, A2).
getopts(A1, A2) -> inet:getopts(A1, A2).
peername(A1) -> inet:peername(A1).
sockname(A1) -> inet:sockname(A1).
port(A1) -> inet:port(A1).

