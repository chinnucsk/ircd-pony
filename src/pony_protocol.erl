-module(pony_protocol).
-export([parse/1, stringify/1, stringify/3]).
-export([render/1, render_numeric/2]).

command_to_atom(X) when is_binary(X) ->
    command_to_atom(binary_to_list(X));
command_to_atom(X) when is_list(X) ->
    case string:to_lower(X) of
        "admin" -> admin;
        "away" -> away;
        "invite" -> invite;
        "join" -> join;
        "kick" -> kick;
        "kill" -> kill;
        "list" -> list;
        "mode" -> mode;
        "motd" -> motd;
        "names" -> names;
        "nick" -> nick;
        "notice" -> notice;
        "oper" -> oper;
        "part" -> part;
        "pass" -> pass;
        "ping" -> ping;
        "privmsg" -> privmsg;
        "quit" -> quit;
        "topic" -> topic;
        "user" -> user;
        "version" -> version;
        "who" -> who;
        "whois" -> whois;
        "whowas" -> whowas;
        _ -> {unknown, X}
    end.

atom_to_command(join) -> "JOIN";
atom_to_command(part) -> "PART";
atom_to_command(ping) -> "PING";
atom_to_command(privmsg) -> "PRIVMSG";
atom_to_command(topic) -> "TOPIC";
atom_to_command(user) -> "USER".

parse_argument(<<$:, X/binary>>) ->
    [X];
parse_argument(<<X/binary>>) ->
    case binary:split(X, <<" ">>) of
        [Head, Tail] -> [Head | parse_argument(Tail)];
        _ -> [X]
    end.

parse_command(Prefix, X) ->
    case binary:split(X, <<" ">>) of
        [Command, Rest] -> {ok, Prefix, command_to_atom(Command), parse_argument(Rest)};
        [Command] -> {ok, Prefix, command_to_atom(Command), []};
        _ -> {error, {missing_command, Prefix, X}}
    end.

parse_prefix(<<$:, X/binary>>) ->
    case binary:split(X, <<" ">>) of
        [Prefix, Rest] -> parse_command(Prefix, Rest);
        _ -> {error, {missing_command, X}}
    end;
parse_prefix(<<>>) ->
    {error, {missing_command}};
parse_prefix(<<Rest/binary>>) ->
    parse_command(<<>>, Rest).

parse(X) when is_binary(X) ->
    parse_prefix(X);
parse(X) when is_list(X) ->
    parse(list_to_binary(X)).

stringify(X) ->
    case parse(X) of
        {ok, Prefix, Command, Arguments} -> stringify(Prefix, Command, Arguments);
        {error, _} -> "Error: Invalid message."
    end.

stringify(P, C, A) ->
    io_lib:format("~p~n", [[{prefix, P}, {command, C}, {args, A}]]).

sep(_Sep, [])      -> [];
sep(_Sep, [X])     -> [X];
sep( Sep, [H | T]) -> [H, Sep | sep(Sep, T)].

render_numeric('RPL_WELCOME', [Nick]) ->
    io_lib:format(":~s 001 ~s :Welcome to the ~s Internet Relay Chat Network ~s",
                 [pony:me(), Nick, pony:description(), Nick]);
render_numeric('RPL_YOURHOST', [Nick]) ->
    io_lib:format(":~s 002 ~s :Your host is ~s, running version ~s",
                 [pony:me(), Nick, pony:server(), pony:version()]);
render_numeric('RPL_NOTOPIC', [Nick, Channel]) ->
    io_lib:format(":~s 331 ~s ~s :No topic is set.",
                  [pony:me(), Nick, Channel]);
render_numeric('RPL_TOPIC', [Nick, Chan, Topic]) ->
    io_lib:format(":~s 332 ~s ~s :~s",
                  [pony:me(), Nick, Chan, Topic]);
render_numeric('RPL_LISTSTART', [Nick]) ->
    io_lib:format(":~s 321 ~s Channel :Users  Topic",
                  [pony:me(), Nick]);
render_numeric('RPL_LIST', [Nick, Chan, Count, Topic]) ->
    io_lib:format(":~s 322 ~s ~s ~B :~s",
                  [pony:me(), Nick, Chan, Count, Topic]);
render_numeric('RPL_LISTEND', [Nick]) ->
    io_lib:format(":~s 323 ~s :End of /LIST",
                  [pony:me(), Nick]);
render_numeric('RPL_NAMREPLY', [Nick, Chan, Names]) ->
    io_lib:format(":~s 353 ~s ~s ~s :~s",
                  [pony:me(), Nick, "=", %% This is a RatBox thing
                   Chan, sep(" ", Names)]);
render_numeric('RPL_ENDOFNAMES', [CurNick, Channel]) ->
    io_lib:format(":~s 366 ~s ~s :End of /NAMES list.",
                  [pony:me(), CurNick, Channel]);
render_numeric('ERR_ERRONEUSNICKNAME', [OldNick, Nick]) ->
    io_lib:format(":~s 432 ~s ~s :Erroneous Nickname",
                  [pony:me(), OldNick, Nick]);
render_numeric('ERR_NOTEXTTOSEND', [Nick]) ->
    io_lib:format(":~s 412 ~s :No text to send",
                  [pony:me(), Nick]);
render_numeric('ERR_NORECIPIENT', [Nick, Cmd]) ->
    io_lib:format(":~s 411 ~s :No recipient given (~s)",
                  [pony:me(), Nick, atom_to_command(Cmd)]);
render_numeric('ERR_NEEDMOREPARAMS', [Nick, Cmd]) ->
    io_lib:format(":~s 461 ~s ~s :Not enough parameters", [pony:me(), Nick,
                                                           atom_to_command(Cmd)]).

render({topic, Source, Channel, Text}) ->
    io_lib:format(":~s TOPIC ~s :~s", [Source, Channel, Text]);
render({part, Source, Channel}) ->
    io_lib:format(":~s PART :~s", [Source, Channel]);
render({join, Source, Channel}) ->
    io_lib:format(":~s JOIN :~s", [Source, Channel]);
render({privmsg, Source, Target, Text}) ->
    io_lib:format(":~s PRIVMSG ~s :~s", [Source, Target, Text]);
render({pong, Server}) ->
    io_lib:format("PONG :~s", [Server]).

