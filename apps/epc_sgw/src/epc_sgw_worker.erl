-module(epc_sgw_worker).
-behaviour(gen_server).
-modified('Date: 1/09/2021').


-export([init/1,handle_info/2,handle_call/3,terminate/2,handle_cast/2]).


-export([start_link/1]).


-define(NAME,?MODULE).
-define(MESSAGES,<<131,100,0,8,109,101,115,115,97,103,101,115>>).
-define(MAX_PAYLOAD_SIZE,1024).
-define(AUTH_TIMEOUT,5000).

-record(state,{
    uid,
    socket,
    ref,
    isVerified=false,
    messages=[]
    }).

%%%%%%%%%%%%%%%%%%% Api %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
start_link(Lsock)->
    gen_server:start_link(?NAME,[Lsock],[]).


init([Lsock])->
    {ok,#state{socket=Lsock},0}.


%%%%%%%%%%%%%% callbacks %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% 
handle_call(Message,From,State)->
    {reply,State,State}.
handle_cast(Message,State)->
    {noreply,State}.
handle_info({tcp_closed,_},State)->
    {stop,socket_closed,State};


handle_info(timeout,State)->
    {ok,Sock}=gen_tcp:accept(State#state.socket),
    create_new_child_procedure(State#state.socket),
    {noreply,State#state{socket=Sock}};

handle_info({tcp,Socket,Message},State)->
    NewState=handle_socket_message(Message,State),
    {noreply,NewState};

handle_info(Message, State)->
    io:format("Unknown message , out of band: ~p",[Message]),
    {noreply,State}.

terminate(socket_closed,State)->
    io:format("Socket closed"),
    ok;
terminate(Reason,State)->
    io:format("terminating,reason:~p",[Reason]),
    ok.

%%%%%%%%%%%%%%%%%%%%%%%%% helper methods %%%%%%%%%%%%%%%%%%%%%%%%%%%%

handle_socket_message(Raw,State)->
    Message=binary_to_term(Raw),
    handle_message(Message, State).


handle_message({verify,Uid},State)->
    Verified=case epc_sgw_registry:get_session(Uid) of
                    {not_found,_}-> gen_tcp:close(State#state.socket),
                                    exit({normal,could_not_verify});
                    {found,_}->
                                    epc_sgw_registry:update_session({
                                                        Uid
                                                        ,make_ref(),
                                                        self()})
              end,
    State#state{isVerified=Verified};

handle_message(_Message,State) when State#state.isVerified=:=false->
    gen_tcp:close(State#state.socket),
    exit({normal,verification_required});

handle_message(messages,State)->
    gen_tcp:send(State#state.socket,term_to_binary(State#state.messages)),
    State;

handle_message(Message,State)->
    gen_tcp:send(State#state.socket,term_to_binary({unkown_message,Message})),
    State.

update_registry(Uid)->
    Ref=make_ref(),
    epc_sgw_registry:update_session({Uid,Ref,self()}),
    Ref.

% creates a new worker and forwards the listening socket to it
create_new_child_procedure(Socket)->
    {ok,Pid}=epc_sgw_worker_sup:start_child(Socket),
    epc_sgw_server:registerChild(Pid).