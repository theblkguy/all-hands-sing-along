defmodule AllHandsSingAlongWeb.StemWorkerController do
  @moduledoc """
  Lets a Mac on your network pull isolation jobs from the hosted app.
  """
  use AllHandsSingAlongWeb, :controller

  alias AllHandsSingAlong.Catalog.StemSeparator

  plug :require_stem_worker_token

  @spec claim(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def claim(conn, _params) do
    case StemSeparator.claim_remote_job() do
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
      case StemSeparator.report_remote_progress(id, pct) do
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
      case StemSeparator.complete_remote_job(id, upload.path, upload.filename) do
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

      case StemSeparator.fail_remote_job(id, reason) do
        :ok -> json(conn, %{ok: true})
        {:error, :not_found} -> send_resp(conn, 404, "")
      end
    else
      :error -> send_resp(conn, 422, "")
    end
  end

  defp require_stem_worker_token(conn, _opts) do
    expected = Application.get_env(:all_hands_sing_along, :stem_worker_token)
    presented = bearer_token(conn)

    if valid_token?(expected, presented) do
      conn
    else
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

  defp valid_token?(expected, presented)
       when is_binary(expected) and expected != "" and is_binary(presented) do
    byte_size(expected) == byte_size(presented) and
      Plug.Crypto.secure_compare(expected, presented)
  end

  defp valid_token?(_, _), do: false

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
