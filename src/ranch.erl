%% Copyright (c) 2011-2012, Loïc Hoguin <essen@ninenines.eu>
%%
%% Permission to use, copy, modify, and/or distribute this software for any
%% purpose with or without fee is hereby granted, provided that the above
%% copyright notice and this permission notice appear in all copies.
%%
%% THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
%% WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
%% MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
%% ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
%% WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
%% ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
%% OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

%% @doc Ranch API to start and stop listeners.
-module(ranch).

-export([start_listener/6, stop_listener/1, child_spec/6, accept_ack/1,
	get_protocol_options/1, set_protocol_options/2]).

%% @doc Start a listener for the given transport and protocol.
%%
%% A listener is effectively a pool of <em>NbAcceptors</em> acceptors.
%% Acceptors accept connections on the given <em>Transport</em> and forward
%% connections to the given <em>Protocol</em> handler. Both transport and
%% protocol modules can be given options through the <em>TransOpts</em> and
%% the <em>ProtoOpts</em> arguments. Available options are documented in the
%% <em>listen</em> transport function and in the protocol module of your choice.
%%
%% All acceptor and connection processes are supervised by the listener.
%%
%% It is recommended to set a large enough number of acceptors to improve
%% performance. The exact number depends of course on your hardware, on the
%% protocol used and on the number of expected simultaneous connections.
%%
%% The <em>Transport</em> option <em>max_connections</em> allows you to define
%% the maximum number of simultaneous connections for this listener. It defaults
%% to 1024. See <em>ranch_listener</em> for more details on limiting the number
%% of connections.
%%
%% <em>Ref</em> can be used to stop the listener later on.
-spec start_listener(any(), non_neg_integer(), module(), any(), module(), any())
	-> {ok, pid()}.
start_listener(Ref, NbAcceptors, Transport, TransOpts, Protocol, ProtoOpts)
		when is_integer(NbAcceptors) andalso is_atom(Transport)
		andalso is_atom(Protocol) ->
	supervisor:start_child(ranch_sup, child_spec(Ref, NbAcceptors,
		Transport, TransOpts, Protocol, ProtoOpts)).

%% @doc Stop a listener identified by <em>Ref</em>.
%%
%% Note that stopping the listener will close all currently running
%% connections abruptly.
-spec stop_listener(any()) -> ok | {error, not_found}.
stop_listener(Ref) ->
	case supervisor:terminate_child(ranch_sup, {ranch_listener_sup, Ref}) of
		ok ->
			supervisor:delete_child(ranch_sup, {ranch_listener_sup, Ref});
		{error, Reason} ->
			{error, Reason}
	end.

%% @doc Return a child spec suitable for embedding.
%%
%% When you want to embed Ranch in another application, you can use this
%% function to create a <em>ChildSpec</em> suitable for use in a supervisor.
%% The parameters are the same as in <em>start_listener/6</em> but rather
%% than hooking the listener to the Ranch internal supervisor, it just returns
%% the spec.
-spec child_spec(any(), non_neg_integer(), module(), any(), module(), any())
	-> supervisor:child_spec().
child_spec(Ref, NbAcceptors, Transport, TransOpts, Protocol, ProtoOpts)
		when is_integer(NbAcceptors) andalso is_atom(Transport)
		andalso is_atom(Protocol) ->
	{{ranch_listener_sup, Ref}, {ranch_listener_sup, start_link, [
		NbAcceptors, Transport, TransOpts, Protocol, ProtoOpts
	]}, permanent, 5000, supervisor, [ranch_listener_sup]}.

%% @doc Acknowledge the accepted connection.
%%
%% Effectively used to make sure the socket control has been given to
%% the protocol process before starting to use it.
-spec accept_ack(pid()) -> ok.
accept_ack(ListenerPid) ->
	receive {shoot, ListenerPid} -> ok end.

%% @doc Return the current protocol options for the given listener.
-spec get_protocol_options(any()) -> any().
get_protocol_options(Ref) ->
	ListenerPid = ref_to_listener_pid(Ref),
	{ok, ProtoOpts} = ranch_listener:get_protocol_options(ListenerPid),
	ProtoOpts.

%% @doc Upgrade the protocol options for the given listener.
%%
%% The upgrade takes place at the acceptor level, meaning that only the
%% newly accepted connections receive the new protocol options. This has
%% no effect on the currently opened connections.
-spec set_protocol_options(any(), any()) -> ok.
set_protocol_options(Ref, ProtoOpts) ->
	ListenerPid = ref_to_listener_pid(Ref),
	ok = ranch_listener:set_protocol_options(ListenerPid, ProtoOpts).

%% Internal.

-spec ref_to_listener_pid(any()) -> pid().
ref_to_listener_pid(Ref) ->
	Children = supervisor:which_children(ranch_sup),
	{_, ListenerSupPid, _, _} = lists:keyfind(
		{ranch_listener_sup, Ref}, 1, Children),
	ListenerSupChildren = supervisor:which_children(ListenerSupPid),
	{_, ListenerPid, _, _} = lists:keyfind(
		ranch_listener, 1, ListenerSupChildren),
	ListenerPid.
