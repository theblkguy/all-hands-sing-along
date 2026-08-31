# lib/all_hands_sing_along_web/live/room_live/auth.ex
defmodule AllHandsSingAlongWeb.RoomLive.Auth do
  @moduledoc false

  require Logger

  import Phoenix.LiveView, only: [put_flash: 3]

  alias AllHandsSingAlong.Queue

  def host_token_from_session(session, code) do
    session
    |> Map.get("host_tokens", %{})
    |> Map.get(code)
  end

  def put_host_token(socket, token) do
    %{socket | private: Map.put(socket.private, :host_token, token)}
  end

  def host_token(socket), do: Map.get(socket.private, :host_token)

  def with_host(socket, fun) do
    if socket.assigns.host? do
      fun.(socket)
    else
      {:noreply, put_flash(socket, :error, "Only the host can do that")}
    end
  end

  def fetch_room_entry(socket, id) do
    with {entry_id, ""} <- Integer.parse(to_string(id)),
         {:ok, entry} <- Queue.get_entry(entry_id),
         true <- entry.room_id == socket.assigns.room.id do
      {:ok, entry}
    else
      _ -> {:error, :not_found}
    end
  end

  def error_text(:unauthorized), do: "Only the host can do that"
  def error_text(:missing_audio), do: "This song still needs audio"
  def error_text(:missing_lyrics), do: "This song still needs lyrics"
  def error_text(:not_installed), do: "Can't strip vocals yet. Run setup on this Mac."
  def error_text(:missing_ffmpeg), do: "Need ffmpeg to mix a quiet guide vocal."

  def error_text(:missing_numpy),
    do: "Can't strip vocals: NumPy is missing. Re-run ./script/setup."

  def error_text(:stem_failed), do: "Couldn't strip the vocals"
  def error_text(:not_ready), do: "Only Ready songs can move"
  def error_text(:not_found), do: "Not found"
  def error_text(:invalid_lrc), do: "That doesn't look like timed .lrc lyrics"
  def error_text(:invalid), do: "Title and artist are required"
  def error_text(:invalid_delta), do: "Invalid lyric offset"
  def error_text(:invalid_direction), do: "Invalid move direction"
  def error_text(:no_synced_lyrics), do: "That match has no timed lyrics"
  def error_text(:ambiguous), do: "A few matches — pick one below"
  def error_text(:none_ready), do: "No ready songs"
  def error_text(:invalid_ext), do: "Unsupported audio type"
  def error_text(:no_file), do: "Choose a file"
  def error_text(:room_full), do: "This room is at the 20-file limit"
  def error_text(:too_large), do: "That file is too large"
  def error_text(:not_accepted), do: "Unsupported audio type"
  def error_text(:too_many_files), do: "Only one file at a time"
  def error_text(:store_failed), do: "Couldn't save that audio"
  def error_text({:http, _status}), do: "Couldn't fetch those lyrics"
  def error_text(%Ecto.Changeset{} = changeset), do: changeset_error(changeset)

  def error_text(reason) do
    Logger.error("unhandled room error: #{inspect(reason)}")

    endpoint = Application.get_env(:all_hands_sing_along, AllHandsSingAlongWeb.Endpoint, [])

    if Keyword.get(endpoint, :debug_errors, false) do
      raise ArgumentError, "unhandled room error: #{inspect(reason)}"
    else
      "Something went wrong"
    end
  end

  defp changeset_error(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.map(fn {field, msgs} -> "#{field} #{Enum.join(msgs, ", ")}" end)
    |> Enum.join("; ")
  end
end
