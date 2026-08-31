defmodule AllHandsSingAlongWeb.UploadController do
  @moduledoc """
  Serves uploaded audio. Local adapter streams from disk; Tigris redirects
  to a short-lived signed URL so the Fly VM does not proxy the bytes.
  """
  use AllHandsSingAlongWeb, :controller

  alias AllHandsSingAlong.Catalog.Uploads

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"filename" => filename}) when is_binary(filename) do
    case Uploads.serve("/uploads/" <> filename) do
      {:file, path} ->
        conn
        |> put_resp_header("accept-ranges", "bytes")
        |> put_resp_content_type(MIME.from_path(path), nil)
        |> send_file(200, path)

      {:redirect, url} ->
        redirect(conn, external: url)

      :not_found ->
        send_resp(conn, 404, "Not Found")
    end
  end
end
