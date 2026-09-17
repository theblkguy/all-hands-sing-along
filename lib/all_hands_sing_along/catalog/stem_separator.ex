# lib/all_hands_sing_along/catalog/stem_separator.ex
defmodule AllHandsSingAlong.Catalog.StemSeparator do
  @moduledoc """
  One-at-a-time vocal isolation jobs. Phoenix never runs Demucs in a LiveView.
  """
  use GenServer

  require Logger
  import Ecto.Query

  alias AllHandsSingAlong.Catalog
  alias AllHandsSingAlong.Catalog.Song
  alias AllHandsSingAlong.Catalog.StemAdapter
  alias AllHandsSingAlong.Catalog.StemCache
  alias AllHandsSingAlong.Catalog.Uploads
  alias AllHandsSingAlong.Queue
  alias AllHandsSingAlong.Repo

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Where vocal removal happens for this deployment:

    * `:cloud`         — a URL-capable adapter (Replicate) runs on the server. No host setup.
    * `:local`         — Demucs is installed on this machine (running the app locally).
    * `:remote_worker` — nothing here can separate; a host's Mac must run `./script/worker`.
    * `:disabled`      — separation turned off in config.
  """
  @spec mode() :: :cloud | :local | :remote_worker | :disabled
  def mode do
    cond do
      not enabled?() -> :disabled
      not adapter_available?() -> :remote_worker
      StemAdapter.remote_capable?(adapter()) -> :cloud
      true -> :local
    end
  end

  @spec vocal_mix() :: float()
  def vocal_mix do
    case Keyword.get(config(), :vocal_mix, 0.12) do
      mix when is_number(mix) and mix >= 0 and mix <= 1 -> mix / 1
      _ -> 0.12
    end
  end

  @spec enqueue(integer()) :: :ok | {:error, term()}
  def enqueue(song_id) when is_integer(song_id) do
    case cached_instrumental(song_id) do
      url when is_binary(url) ->
        # Someone, somewhere, already separated these exact bytes. Skip the queue.
        finish_job(song_id, {:ok, url})

      nil ->
        do_enqueue(song_id)
    end
  end

  defp do_enqueue(song_id) do
    cond do
      not enabled?() ->
        mark_failed(song_id, :not_installed)

      not adapter_available?() ->
        mark_status_id(song_id, :queued, nil)
        :ok

      sync?() ->
        finish_job(song_id, perform_job(song_id))

      true ->
        GenServer.cast(__MODULE__, {:enqueue, song_id})
    end
  end

  @spec cancel(integer()) :: :ok
  def cancel(song_id) when is_integer(song_id) do
    if sync?() do
      mark_idle(song_id)
      :ok
    else
      GenServer.call(__MODULE__, {:cancel, song_id})
    end
  end

  @spec retry(integer()) :: :ok | {:error, term()}
  def retry(song_id) when is_integer(song_id), do: enqueue(song_id)

  @spec claim_remote_job(integer()) :: {:ok, Song.t()} | :empty
  def claim_remote_job(room_id) when is_integer(room_id) do
    case next_queued_song(room_id) do
      nil ->
        :empty

      song ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        {count, _} =
          Song
          |> where([s], s.id == ^song.id and s.stem_status == :queued)
          |> Repo.update_all(
            set: [
              stem_status: :running,
              stem_error: nil,
              stem_progress: 0,
              updated_at: now
            ]
          )

        if count == 1 do
          claimed = Repo.get!(Song, song.id)
          Queue.broadcast_queue(claimed.room_id)
          {:ok, claimed}
        else
          claim_remote_job(room_id)
        end
    end
  end

  @spec report_remote_progress(integer(), integer(), integer()) :: :ok | {:error, :not_found}
  def report_remote_progress(room_id, song_id, pct)
      when is_integer(room_id) and is_integer(song_id) and is_integer(pct) do
    case song_in_room(room_id, song_id) do
      {:ok, %Song{stem_status: :running} = song} ->
        report_progress(song, pct)
        :ok

      {:ok, _} ->
        :ok

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @spec complete_remote_job(integer(), integer(), String.t(), String.t()) ::
          :ok | {:error, term()}
  def complete_remote_job(room_id, song_id, source_path, client_name)
      when is_integer(room_id) and is_integer(song_id) and is_binary(source_path) and
             is_binary(client_name) do
    case song_in_room(room_id, song_id) do
      {:error, :not_found} ->
        {:error, :not_found}

      {:ok, %Song{stem_status: status} = song} when status != :running ->
        if Catalog.playable?(song), do: :ok, else: {:error, :not_running}

      {:ok, %Song{} = song} ->
        with {:ok, url} <- Uploads.store_audio!(source_path, client_name) do
          finish_job(song.id, {:ok, url})
        end
    end
  end

  @spec fail_remote_job(integer(), integer(), term()) :: :ok | {:error, :not_found}
  def fail_remote_job(room_id, song_id, reason)
      when is_integer(room_id) and is_integer(song_id) do
    case song_in_room(room_id, song_id) do
      {:ok, %Song{stem_status: :running}} ->
        finish_job(song_id, {:error, reason})
        :ok

      {:ok, _} ->
        :ok

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @impl true
  def init(_opts) do
    {:ok, %{queue: :queue.new(), current: nil}}
  end

  @impl true
  def handle_cast({:enqueue, song_id}, state) do
    {:noreply, state |> push(song_id) |> maybe_start()}
  end

  @impl true
  def handle_call({:cancel, song_id}, _from, state) do
    state = drop_queued(state, song_id)

    state =
      case state.current do
        %{song_id: ^song_id} = current ->
          stop_current(current)
          mark_idle(song_id)
          maybe_start(%{state | current: nil})

        _ ->
          mark_idle(song_id)
          state
      end

    {:reply, :ok, state}
  end

  @impl true
  def handle_info({ref, result}, %{current: %{ref: ref, song_id: song_id}} = state)
      when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    finish_job(song_id, result)
    {:noreply, maybe_start(%{state | current: nil})}
  end

  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %{current: %{ref: ref, song_id: song_id}} = state
      ) do
    finish_job(song_id, {:error, reason_to_error(reason)})
    {:noreply, maybe_start(%{state | current: nil})}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp maybe_start(%{current: %{}} = state), do: state

  defp maybe_start(state) do
    case :queue.out(state.queue) do
      {:empty, _queue} ->
        state

      {{:value, song_id}, rest} ->
        case start_job(song_id) do
          {:ok, current} -> %{state | queue: rest, current: current}
          :skip -> maybe_start(%{state | queue: rest})
        end
    end
  end

  defp start_job(song_id) do
    song = Repo.get(Song, song_id)

    cond do
      is_nil(song) ->
        :skip

      Catalog.playable?(song) ->
        :skip

      not Catalog.needs_isolation?(song) ->
        :skip

      true ->
        mark_status(song, :running, nil)
        task = Task.async(fn -> perform_job(song_id) end)
        {:ok, %{song_id: song_id, ref: task.ref, task: task}}
    end
  end

  defp stop_current(%{task: task}) do
    _ = Task.shutdown(task, :brutal_kill)
    :ok
  end

  defp stop_current(_), do: :ok

  defp push(state, song_id) do
    already? = match?(%{song_id: ^song_id}, state.current)
    queued? = song_id in :queue.to_list(state.queue)

    if already? or queued? do
      state
    else
      mark_status_id(song_id, :queued, nil)
      %{state | queue: :queue.in(song_id, state.queue)}
    end
  end

  defp drop_queued(state, song_id) do
    rest =
      state.queue
      |> :queue.to_list()
      |> Enum.reject(&(&1 == song_id))
      |> :queue.from_list()

    %{state | queue: rest}
  end

  defp perform_job(song_id) do
    case Repo.get(Song, song_id) do
      nil ->
        :skip

      song ->
        cond do
          Catalog.playable?(song) -> :skip
          not Catalog.needs_isolation?(song) -> :skip
          true -> isolate_and_store(song)
        end
    end
  end

  defp isolate_and_store(%Song{} = song) do
    with {:ok, produced} <- isolate(song),
         {:ok, url} <- Uploads.store_audio!(produced, Path.basename(produced)) do
      {:ok, url}
    end
  end

  # Cloud adapters fetch the original themselves from a presigned URL, so the
  # Fly VM never downloads it. Local adapters need the file on disk.
  defp isolate(%Song{} = song) do
    adapter = adapter()
    progress = &report_progress(song, &1)

    with {:remote, {:ok, url}} <- {:remote, remote_source(adapter, song)} do
      adapter.isolate_url(url, progress)
    else
      {:remote, :local} ->
        with {:ok, input} <- input_file(song) do
          adapter.isolate(input, progress)
        end

      {:remote, {:error, reason}} ->
        {:error, reason}
    end
  end

  defp remote_source(adapter, %Song{} = song) do
    cond do
      not StemAdapter.remote_capable?(adapter) ->
        :local

      absolute_url?(Uploads.public_url(song.original_path)) ->
        {:ok, Uploads.public_url(song.original_path)}

      # Local uploads adapter (dev) + cloud separator: fall back to shipping the file.
      is_binary(Uploads.local_path(song.original_path)) ->
        :local

      true ->
        {:error, :missing_audio}
    end
  end

  defp absolute_url?(url) when is_binary(url),
    do: String.starts_with?(url, ["http://", "https://"])

  defp absolute_url?(_), do: false

  defp cached_instrumental(song_id) do
    case Repo.get(Song, song_id) do
      %Song{content_hash: hash} = song when is_binary(hash) ->
        if Catalog.needs_isolation?(song), do: StemCache.lookup(hash, vocal_mix()), else: nil

      _ ->
        nil
    end
  end

  defp report_progress(%Song{} = song, pct) when is_integer(pct) do
    pct = pct |> max(0) |> min(100)
    now = System.monotonic_time(:millisecond)
    last_ms = Process.get(:stem_progress_ms, 0)
    last_pct = Process.get(:stem_progress_pct, -1)

    if pct >= 100 or pct - last_pct >= 5 or now - last_ms >= 500 do
      Process.put(:stem_progress_ms, now)
      Process.put(:stem_progress_pct, pct)

      case Repo.get(Song, song.id) do
        nil ->
          :ok

        current ->
          _ = Catalog.update_song(current, %{stem_progress: pct})
          Queue.broadcast_queue(current.room_id)
      end
    end

    :ok
  end

  defp finish_job(_song_id, :skip), do: :ok

  defp finish_job(song_id, {:ok, url}) when is_binary(url) do
    case Repo.get(Song, song_id) do
      nil ->
        :ok

      song ->
        case Catalog.update_song(song, %{
               instrumental_path: url,
               stem_status: :ok,
               stem_error: nil,
               stem_progress: 100
             }) do
          {:ok, updated} ->
            StemCache.put(updated.content_hash, vocal_mix(), url, Atom.to_string(mode()))
            Queue.sync_entries_for_song(updated)

          {:error, _} ->
            mark_failed(song_id, :stem_failed)
        end
    end
  end

  defp finish_job(song_id, {:error, reason}) do
    mark_failed(song_id, reason)
  end

  defp finish_job(song_id, _other) do
    mark_failed(song_id, :stem_failed)
  end

  defp input_file(%Song{} = song) do
    case Uploads.local_path(song.original_path) do
      path when is_binary(path) ->
        if File.exists?(path), do: {:ok, path}, else: {:error, :missing_audio}

      _ ->
        {:error, :missing_audio}
    end
  end

  defp mark_failed(song_id, reason) do
    Logger.error("vocal removal failed for song #{song_id}: #{inspect(reason)}")
    mark_status_id(song_id, :failed, error_message(reason))

    case Repo.get(Song, song_id) do
      nil -> :ok
      song -> Queue.sync_entries_for_song(song)
    end
  end

  defp mark_idle(song_id), do: mark_status_id(song_id, :idle, nil)

  defp mark_status_id(song_id, status, error) do
    case Repo.get(Song, song_id) do
      nil -> :ok
      song -> mark_status(song, status, error)
    end
  end

  defp mark_status(%Song{} = song, status, error) do
    progress =
      case status do
        :queued -> 0
        :idle -> 0
        :ok -> 100
        _ -> song.stem_progress || 0
      end

    _ =
      Catalog.update_song(song, %{
        stem_status: status,
        stem_error: error,
        stem_progress: progress
      })

    Queue.broadcast_queue(song.room_id)
    :ok
  end

  # Shown in the queue row to everyone in the room, so it stays free of shell
  # commands and vendor names; mark_failed/2 logs the real reason for the host.
  defp error_message(reason) when reason in [:not_installed, :missing_numpy, :missing_ffmpeg],
    do: "Vocal removal isn't set up yet. The host can use Play original."

  defp error_message(reason) when reason in [:replicate_unauthorized, :replicate_billing],
    do: "Vocal removal is unavailable right now. The host can use Play original."

  defp error_message(:missing_audio), do: "That song's audio file is missing."

  defp error_message(:timeout),
    do: "Vocal removal took too long. The host can retry or use Play original."

  defp error_message(_), do: "Couldn't remove the vocals"

  defp reason_to_error(_), do: :stem_failed

  defp next_queued_song(room_id) do
    Song
    |> where([s], s.room_id == ^room_id)
    |> where([s], s.stem_status == :queued)
    |> where([s], not is_nil(s.original_path) and s.original_path != "")
    |> where([s], is_nil(s.instrumental_path) or s.instrumental_path == "")
    |> order_by([s], asc: s.id)
    |> limit(1)
    |> Repo.one()
  end

  defp song_in_room(room_id, song_id) do
    case Repo.get(Song, song_id) do
      %Song{room_id: ^room_id} = song -> {:ok, song}
      _ -> {:error, :not_found}
    end
  end

  defp adapter_available? do
    adapter().available?()
  end

  defp adapter do
    Keyword.get(config(), :adapter, AllHandsSingAlong.Catalog.DemucsStemAdapter)
  end

  defp sync?, do: Keyword.get(config(), :sync, false) == true

  defp enabled?, do: Keyword.get(config(), :enabled, true) != false

  defp config do
    Application.get_env(:all_hands_sing_along, __MODULE__, [])
  end
end
