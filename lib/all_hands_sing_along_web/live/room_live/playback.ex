# lib/all_hands_sing_along_web/live/room_live/playback.ex
defmodule AllHandsSingAlongWeb.RoomLive.Playback do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [connected?: 1, push_event: 3, put_flash: 3]

  alias AllHandsSingAlong.Rooms
  alias AllHandsSingAlongWeb.RoomLive.Auth
  alias AllHandsSingAlongWeb.RoomLive.Lyrics

  def play(socket) do
    Auth.with_host(socket, fn socket ->
      socket = Lyrics.close_preview(socket)

      case Rooms.play(socket.assigns.room, Auth.host_token(socket)) do
        {:ok, playback} -> {:noreply, sync(socket, playback)}
        {:error, reason} -> {:noreply, put_flash(socket, :error, Auth.error_text(reason))}
      end
    end)
  end

  def pause(socket) do
    Auth.with_host(socket, fn socket ->
      case Rooms.pause(socket.assigns.room, Auth.host_token(socket)) do
        {:ok, playback} -> {:noreply, sync(socket, playback)}
        {:error, reason} -> {:noreply, put_flash(socket, :error, Auth.error_text(reason))}
      end
    end)
  end

  def skip(socket) do
    Auth.with_host(socket, fn socket ->
      socket = Lyrics.close_preview(socket)

      case Rooms.skip(socket.assigns.room, Auth.host_token(socket)) do
        {:ok, playback} -> {:noreply, sync(socket, playback)}
        {:error, reason} -> {:noreply, put_flash(socket, :error, Auth.error_text(reason))}
      end
    end)
  end

  def sync(socket, playback) do
    socket
    |> assign(:playback, playback)
    |> push_sync()
  end

  def push_sync(socket) do
    if connected?(socket) do
      push_event(socket, "player-sync", player_payload(socket, socket.assigns.playback))
    else
      socket
    end
  end

  defp player_payload(socket, playback) do
    previewing? = socket.assigns.host? and not is_nil(socket.assigns.lyric_preview)

    base = %{
      muted: previewing?,
      show_controls: not previewing?
    }

    case playback do
      nil ->
        Map.merge(base, %{
          playing: false,
          position_ms: 0,
          server_time_ms: System.system_time(:millisecond),
          audio_url: nil,
          lyrics: [],
          offset_ms: 0
        })

      playback ->
        Map.merge(base, %{
          playing: playback.playing?,
          position_ms: playback.position_ms,
          server_time_ms: playback.server_time_ms,
          audio_url: playback.audio_url,
          lyrics: playback.lyrics,
          offset_ms: Map.get(playback, :offset_ms, 0)
        })
    end
  end
end
