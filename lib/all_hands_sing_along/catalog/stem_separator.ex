# lib/all_hands_sing_along/catalog/stem_separator.ex
defmodule AllHandsSingAlong.Catalog.StemSeparator do
  @moduledoc """
  One-at-a-time vocal isolation jobs. Phoenix never runs Demucs in a LiveView.
  """
  use GenServer

  alias AllHandsSingAlong.Catalog
  alias AllHandsSingAlong.Catalog.Song
  alias AllHandsSingAlong.Catalog.Uploads
  alias AllHandsSingAlong.Queue
  alias AllHandsSingAlong.Repo

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec enqueue(integer()) :: :ok | {:error, term()}
  def enqueue(song_id) when is_integer(song_id) do
    cond do
      not enabled?() ->
        mark_failed(song_id, :not_installed)

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
    with {:ok, input} <- input_file(song),
         {:ok, produced} <- adapter().isolate(input, &report_progress(song, &1)),
         {:ok, url} <- Uploads.store_audio!(produced, Path.basename(produced)) do
      {:ok, url}
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
          {:ok, updated} -> Queue.sync_entries_for_song(updated)
          {:error, _} -> mark_failed(song_id, :stem_failed)
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

  defp error_message(:not_installed), do: "Vocal isolation isn’t installed on this machine"

  defp error_message(:missing_numpy),
    do: "Vocal isolation is missing NumPy. Run .venv/bin/python -m pip install numpy"

  defp error_message(:missing_audio), do: "Original audio is missing"
  defp error_message(_), do: "Couldn't remove vocals"

  defp reason_to_error(_), do: :stem_failed

  defp adapter do
    Keyword.get(config(), :adapter, AllHandsSingAlong.Catalog.DemucsStemAdapter)
  end

  defp sync?, do: Keyword.get(config(), :sync, false) == true

  defp enabled?, do: Keyword.get(config(), :enabled, true) != false

  defp config do
    Application.get_env(:all_hands_sing_along, __MODULE__, [])
  end
end
