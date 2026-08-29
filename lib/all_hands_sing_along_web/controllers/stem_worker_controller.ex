defmodule AllHandsSingAlongWeb.StemWorkerController do
  @moduledoc """
  Lets a host's Mac pull isolation jobs for that room only.
  """
  use AllHandsSingAlongWeb, :controller

  alias AllHandsSingAlong.Catalog.StemSeparator
  alias AllHandsSingAlong.Rooms

  plug :require_room_host

  @spec claim(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def claim(conn, _params) do
    case StemSeparator.claim_remote_job(conn.assigns.worker_room.id) do
      {:ok, song} ->
        json(conn, %{
          id: song.id,
          title: song.title,
          original_path: song.original_path
        })

      :empty ->
        send_resp(conn, 204, "")
    end
  end

  @spec progress(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def progress(conn, params) do
    with {:ok, id} <- parse_id(params["id"]),
         {:ok, pct} <- parse_percent(params) do
      case StemSeparator.report_remote_progress(conn.assigns.worker_room.id, id, pct) do
        :ok -> json(conn, %{ok: true})
        {:error, :not_found} -> send_resp(conn, 404, "")
      end
    else
      :error -> send_resp(conn, 422, "")
    end
  end

  @spec complete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def complete(conn, %{"instrumental" => %Plug.Upload{} = upload} = params) do
    with {:ok, id} <- parse_id(params["id"]) do
      case StemSeparator.complete_remote_job(
             conn.assigns.worker_room.id,
             id,
             upload.path,
             upload.filename
           ) do
        :ok -> json(conn, %{ok: true})
        {:error, :not_found} -> send_resp(conn, 404, "")
        {:error, :not_running} -> send_resp(conn, 409, "")
        {:error, :invalid_ext} -> send_resp(conn, 422, "")
        {:error, _} -> send_resp(conn, 422, "")
      end
    else
      :error -> send_resp(conn, 422, "")
    end
  end

  def complete(conn, _params), do: send_resp(conn, 422, "")

  @spec fail(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def fail(conn, params) do
    with {:ok, id} <- parse_id(params["id"]) do
      reason = fail_reason(params)

      case StemSeparator.fail_remote_job(conn.assigns.worker_room.id, id, reason) do
        :ok -> json(conn, %{ok: true})
        {:error, :not_found} -> send_resp(conn, 404, "")
      end
    else
      :error -> send_resp(conn, 422, "")
    end
  end

  defp require_room_host(conn, _opts) do
    code = conn.params["code"]
    token = bearer_token(conn)

    with {:ok, room} <- Rooms.get_room_by_code(code),
         :ok <- Rooms.authorize_host(room, token) do
      assign(conn, :worker_room, room)
    else
      _ ->
        conn
        |> send_resp(401, "")
        |> halt()
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> String.trim(token)
      ["bearer " <> token] -> String.trim(token)
      _ -> nil
    end
  end

  defp parse_id(id) when is_integer(id), do: {:ok, id}

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> {:ok, int}
      _ -> :error
    end
  end

  defp parse_id(_), do: :error

  defp parse_percent(%{"percent" => pct}) when is_integer(pct), do: {:ok, pct}

  defp parse_percent(%{"percent" => pct}) when is_binary(pct) do
    case Integer.parse(pct) do
      {int, ""} -> {:ok, int}
      _ -> :error
    end
  end

  defp parse_percent(_), do: :error

  defp fail_reason(%{"reason" => "not_installed"}), do: :not_installed
  defp fail_reason(%{"reason" => "missing_numpy"}), do: :missing_numpy
  defp fail_reason(%{"reason" => "missing_audio"}), do: :missing_audio
  defp fail_reason(_), do: :stem_failed
end
