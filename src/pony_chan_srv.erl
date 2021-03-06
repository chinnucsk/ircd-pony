%%%-------------------------------------------------------------------
%%% @author Jesper Louis Andersen <>
%%% @copyright (C) 2012, Jesper Louis Andersen
%%% @doc Manage channels in Pony
%%% @end
%%% Created :  5 Jul 2012 by Jesper Louis Andersen <>
%%%-------------------------------------------------------------------
-module(pony_chan_srv).

-behaviour(gen_server).

%% API
-export([start_link/0,
         join/1,
         part/1,
         quits/2
        ]).

-export([channel_members/1,
         list_channels/0,
         set_topic/3,
         topic/1,
         part_channel/1,
         join_channel/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).


-define(TAB, pony_channel_map).
-define(CHAN_TAB, pony_channel_meta).
-define(SERVER, ?MODULE). 

-record(channel,
        { name :: binary(),
          topic :: binary() | undefined }).

-record(state, {}).

%%%===================================================================

%% @doc
%% Starts the server
%% @end
%%--------------------------------------------------------------------
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

join(ChanName) ->
    gen_server:call(?SERVER, {join, ChanName}).

part(ChanName) ->
    gen_server:call(?SERVER, {part, ChanName}).

quits(Pid, Name) ->
    gen_server:cast(?SERVER, {quits, Pid, Name}).

channel_members(Channel) ->
    [Pid || {Pid, _} <- gproc:lookup_local_properties({channel, Channel})].

list_channels() ->
    Channels = ets:match_object(?CHAN_TAB, '_'),
    [{N, length(channel_members(N)), T} || #channel { topic = T, name = N} <- Channels].

part_channel(Channel) ->
    gproc:unreg({p, l, {channel, Channel}}).

join_channel(Channel) ->
    gproc:add_local_property({channel, Channel}, client).

set_topic(Who, Channel, Topic) ->
    gen_server:call(?SERVER, {set_topic, Who, Channel, Topic}).

topic(Channel) ->
    [#channel { topic = T}] = ets:lookup(?CHAN_TAB, Channel),
    case T of
        undefined -> no_topic;
        T -> {topic, T}
    end.
        
%%%===================================================================

%% @private
init([]) ->
    ets:new(?CHAN_TAB, [named_table, public, set, {keypos, #channel.name}]),
    ets:new(?TAB, [named_table, protected, bag]),
    {ok, #state{}}.

%% @private
handle_call({set_topic, Who, Channel, Topic}, _From, State) ->
    [Chan] = ets:lookup(?CHAN_TAB, Channel),
    ets:insert(?CHAN_TAB, Chan#channel{ topic = Topic }),
    [pony_client:msg(Pid, {topic, Who, Channel, Topic})
     || Pid <- channel_members(Channel)],
    {reply, ok, State};
handle_call({join, ChanName}, {Pid, _Tag}, State) ->
    case ets:lookup(?CHAN_TAB, ChanName) of
        [] ->
            ets:insert(?CHAN_TAB, #channel { name = ChanName,
                                             topic = undefined });
        [_] ->
            ok
    end,
    ets:insert(?TAB, {Pid, ChanName}),
    {reply, ok, State};
handle_call({part, ChanName}, {Pid, _Tag}, State) ->
    ets:delete(?TAB, {Pid, ChanName}),
    case channel_members(ChanName) of
        [] ->
            ets:delete(?CHAN_TAB, ChanName);
        [_|_] ->
            ok
    end,
    {reply, ok, State};
handle_call(Request, _From, State) ->
    lager:warning("Unknown Request: ~p", [Request]),
    Reply = ok,
    {reply, Reply, State}.

%% @private
handle_cast({quits, Nick, Pid}, State) when is_pid(Pid) ->
    %% @todo Fix this hack later
    [pony_client:msg(C, {part, Nick, Channel})
     || {_, Channel} <- ets:lookup(?TAB, Pid),
        C <- channel_members(Channel)],
    %% Channels = [Chan || {_, Chan} <- ets:lookup(?TAB, Pid)],
    %% Clients = lists:usort(
    %%             lists:flatmap(fun channel_members/1, Channels)),
    %% [pony_client:msg(C, {quit, Nick}) || C <- Clients],
    {noreply, State};
handle_cast(Msg, State) ->
    lager:warning("Unknown Msg: ~p", [Msg]),
    {noreply, State}.

%% @private
handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, _State) ->
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
