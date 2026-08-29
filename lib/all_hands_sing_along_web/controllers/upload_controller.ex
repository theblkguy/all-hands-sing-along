defmodule AllHandsSingAlongWeb.UploadController do
  @moduledoc """
  Serves uploaded audio from the configured uploads directory.

  Plug.Static cannot use a runtime volume path, so production files on
  `UPLOADS_PATH` are served here.
  """
  use AllHandsSingAlongWeb, :controller

  alias AllHandsSingAlong.Catalog.Uploads

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"filename" => filename}) when is_binary(filename) do
    case Uploads.local_path("/uploads/" <> filename) do
      path when is_binary(path) ->
        if File.regular?(path) do
          conn
          |> put_resp_header("accept-ranges", "bytes")
          |> put_resp_content_type(MIME.from_path(path), nil)
          |> send_file(200, path)
        else
          send_resp(conn, 404, "Not Found")
        end

      _ ->
        send_resp(conn, 404, "Not Found")
    end
  end
end
