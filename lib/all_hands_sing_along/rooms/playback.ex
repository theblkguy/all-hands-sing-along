# lib/all_hands_sing_along/rooms/playback.ex
defmodule AllHandsSingAlong.Rooms.Playback do
  @moduledoc """
  Per-room playhead. Durable queue lives in SQLite; this process only
  tracks now-playing clock state.
  """
  use GenServer

  alias AllHandsSingAlong.Queue
  alias AllHandsSingAlong.Rooms.PlaybackSupervisor
  alias AllHandsSingAlong.Rooms.Sync

  @type snapshot :: %{
          optional(atom()) => term(),
          playing?: boolean(),
          position_ms: non_neg_integer(),
          server_time_ms: integer(),
          audio_url: String.t() | nil,
          lyrics: [Sync.lyric_line()],
          title: String.t() | nil,
          artist: String.t() | nil,
          singer_name: String.t() | nil,
          offset_ms: integer()
        }

  defstruct room_id: nil,
            room_code: nil,
            playing?: false,
            position_ms: 0,
            origin_mono_ms: 0,
            audio_url: nil,
            lyrics: [],
            title: nil,
            artist: nil,
            singer_name: nil,
            offset_ms: 0

  @spec start_link(integer()) :: GenServer.on_start()
  def start_link(room_id) do
    GenServer.start_link(__MODULE__, room_id, name: via(room_id))
  end

  @spec play(integer(), map()) :: :ok | {:error, :not_found}
  def play(room_id, track) when is_integer(room_id) and is_map(track) do
    with {:ok, pid} <- ensure_started(room_id) do
      GenServer.call(pid, {:play, track})
    end
  end

  @spec pause(integer()) :: :ok | {:error, :not_found}
  def pause(room_id) when is_integer(room_id) do
    with {:ok, pid} <- lookup(room_id) do
      GenServer.call(pid, :pause)
    end
  end

  @spec resume(integer()) :: :ok | {:error, :not_found}
  def resume(room_id) when is_integer(room_id) do
    with {:ok, pid} <- lookup(room_id) do
      GenServer.call(pid, :resume)
    end
  end

  @spec nudge_offset(integer(), integer()) :: :ok | {:error, :not_found}
  def nudge_offset(room_id, delta_ms) when is_integer(room_id) and is_integer(delta_ms) do
    with {:ok, pid} <- lookup(room_id) do
      GenServer.call(pid, {:nudge_offset, delta_ms})
    end
  end

  @spec get(integer()) :: snapshot() | nil
  def get(room_id) when is_integer(room_id) do
    case lookup(room_id) do
      {:ok, pid} -> GenServer.call(pid, :get)
      {:error, :not_found} -> nil
    end
  end

  @spec stop(integer()) :: :ok
  def stop(room_id) when is_integer(room_id) do
    case lookup(room_id) do
      {:ok, pid} ->
        _ = DynamicSupervisor.terminate_child(PlaybackSupervisor, pid)
        :ok

      {:error, :not_found} ->
        :ok
    end
  end

  @spec stop_all() :: :ok
  def stop_all do
    PlaybackSupervisor
    |> DynamicSupervisor.which_children()
    |> Enum.each(fn
      {:undefined, pid, :worker, _} when is_pid(pid) ->
        _ = DynamicSupervisor.terminate_child(PlaybackSupervisor, pid)

      _ ->
        :ok
    end)

    :ok
  end

  @impl true
  def init(room_id) do
    {:ok, %__MODULE__{room_id: room_id, origin_mono_ms: monotonic_ms()}}
  end

  @impl true
  def handle_call({:play, track}, _from, state) do
    state =
      state
      |> merge_track(track)
      |> Map.put(:playing?, true)
      |> Map.put(:position_ms, Map.get(track, :position_ms, 0))
      |> Map.put(:offset_ms, 0)
      |> Map.put(:origin_mono_ms, monotonic_ms())

    snapshot = snapshot(state)
    broadcast(state, {:playback, snapshot})
    {:reply, :ok, state}
  end

  def handle_call(:pause, _from, state) do
    state = %{
      state
      | playing?: false,
        position_ms: current_position_ms(state),
        origin_mono_ms: monotonic_ms()
    }

    snapshot = snapshot(state)
    broadcast(state, {:playback, snapshot})
    {:reply, :ok, state}
  end

  def handle_call(:resume, _from, %{audio_url: nil} = state) do
    {:reply, {:error, :not_found}, state}
  end

  def handle_call(:resume, _from, state) do
    state = %{state | playing?: true, origin_mono_ms: monotonic_ms()}
    snapshot = snapshot(state)
    broadcast(state, {:playback, snapshot})
    {:reply, :ok, state}
  end

  def handle_call({:nudge_offset, delta_ms}, _from, state) do
    offset = state.offset_ms + delta_ms
    offset = offset |> max(-15_000) |> min(15_000)
    state = %{state | offset_ms: offset}
    snapshot = snapshot(state)
    broadcast(state, {:playback, snapshot})
    {:reply, :ok, state}
  end

  def handle_call(:get, _from, state) do
    {:reply, snapshot(state), state}
  end

  defp merge_track(state, track) do
    %{
      state
      | room_code: Map.get(track, :room_code, state.room_code),
        audio_url: Map.get(track, :audio_url, state.audio_url),
        lyrics: Map.get(track, :lyrics, state.lyrics) || [],
        title: Map.get(track, :title, state.title),
        artist: Map.get(track, :artist, state.artist),
        singer_name: Map.get(track, :singer_name, state.singer_name)
    }
  end

  defp current_position_ms(%{playing?: false, position_ms: position_ms}), do: position_ms

  defp current_position_ms(state) do
    state.position_ms + (monotonic_ms() - state.origin_mono_ms)
  end

  defp snapshot(state) do
    position_ms = current_position_ms(state)

    %{
      playing?: state.playing?,
      position_ms: position_ms,
      server_time_ms: System.system_time(:millisecond),
      audio_url: state.audio_url,
      lyrics: state.lyrics,
      title: state.title,
      artist: state.artist,
      singer_name: state.singer_name,
      offset_ms: state.offset_ms
    }
  end

  defp broadcast(%{room_code: code}, message) when is_binary(code) do
    Phoenix.PubSub.broadcast(AllHandsSingAlong.PubSub, Queue.topic(code), message)
  end

  defp broadcast(_state, _message), do: :ok

  defp ensure_started(room_id) do
    case lookup(room_id) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, :not_found} ->
        case DynamicSupervisor.start_child(PlaybackSupervisor, {__MODULE__, room_id}) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp lookup(room_id) do
    case Registry.lookup(AllHandsSingAlong.Rooms.Registry, room_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  defp via(room_id), do: {:via, Registry, {AllHandsSingAlong.Rooms.Registry, room_id}}

  defp monotonic_ms, do: System.monotonic_time(:millisecond)
end
