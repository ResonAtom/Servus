defmodule Servus.ClientHandler do
  @moduledoc """
  Handles the socket connection of a client (player). All messages are
  received via tcp and interpreted as JSON.
  """
  alias Servus.PidStore
  alias Servus.ModuleStore
  alias Servus.Serverutils
  alias Servus.PlayerQueue
  alias Servus.Serverutils
  require Logger

  def run(state) do
    case Serverutils.recv(state.socket) do
      {:ok, message} ->
        data = Poison.decode message, as: Servus.Message
        case data do
          #OLD USAGE!!
          {:ok, %{type: "join", value: name}} ->
            # The special `join` message

            # Double join?
            if Map.has_key?(state, :player) do
              Logger.warn "A player already joined on this connection"
              run(state)
            else
              Logger.info "#{name} has joined the queue"

              # Create a new player and add it to the queue
              player = %{
                name: name,
                registered: false, 
                socket: state.socket, 
                id: Serverutils.get_unique_id
              }

              PlayerQueue.push(state.queue, player)

              # Store the player in the process state
              run(Map.put(state, :player, player))
            end
            {:ok, %{type: "login"}} ->
              player = %{
                name: name, 
                registered: true,
                socket: state.socket, 
                id: Serverutils.get_unique_id
              }
              # Store the player in the process state
              run(Map.put(state, :player, player))
            end
            {:ok, %{type: "start_random_game"}} ->
              PlayerQueue.push(state.queue, state.‚player)  
            end
            {:ok, %{type: "start_game_with_id", value: value}} ->
              nil‚
            end
            {:ok, %{type: type, target: target, value: value}} ->
              if target == nil do
                # Generic message from client (player)

                # Check if the game state machine has already been started
                # by querying it's pid from the PidStore. This is only
                # required if it's not already stored in the process state
                if not Map.has_key?(state, :fsm) do
                  pid = PidStore.get(state.player.id)
                  if pid != nil do
                    state = Map.put(state, :fsm, pid)
                  end
                end

                # Try to get the pid of the game state machine and send
                # the command
                pid = state.fsm
                if pid != nil do
                  :gen_fsm.send_event(pid, {state.player.id, type, value})
                end

              else

                # Call external module
                pid = ModuleStore.get(target)

                # Check if the module is registered and available
                # and if yes...
                if pid != nil and Process.alive?(pid) do
                  # ...invoke a synchronous call and send the result back
                  # to the calles (client socket)
                  result = GenServer.call(pid, {type, value})
                  Serverutils.send(state.socket, target, result)
                end
              end

              run(state)
          _ ->
            Logger.warn "Invalid message format: #{message}"
            run(state)
        end
      {:error, err} ->
        # Client has aborted the connection
        # De-register it's ID from the pid store
        if Map.has_key?(state, :player) do
          # Remove him from the queue in case he's still there
          PlayerQueue.remove(state.queue, state.player)

          pid = PidStore.get(state.player.id)
          if pid != nil do
            # Notify the game logic about the player disconnect
            :gen_fsm.send_all_state_event(pid, {:abort, state.player})

            # Remove the player from the registry
            PidStore.remove(state.player.id)

            Logger.info "Removed player from pid store"
          end
        end

        Logger.warn "Unexpected clientside abort"
    end
  end
end
