defmodule Mix.Tasks.Stems.Worker do
  @moduledoc """
  Pulls vocal-isolation jobs for one room from the hosted site and runs Demucs.

      mix stems.worker --room ABC123 --token HOST_TOKEN
      ./script/worker --room ABC123 --token HOST_TOKEN
  """
  use Mix.Task

  alias AllHandsSingAlong.Catalog.DemucsStemAdapter

  @shortdoc "Run Demucs for one hosted karaoke room"

  @default_url "https://all-hands-sing-along.fly.dev"
  @poll_ms 2_000
  @http_timeout 180_000

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:req)

    {opts, _rest} =
      OptionParser.parse!(args,
        strict: [url: :string, token: :string, room: :string],
        aliases: [u: :url, r: :room, t: :token]
      )

    url = opts[:url] || System.get_env("STEM_SITE_URL") || @default_url
    token = opts[:token] || System.get_env("STEM_WORKER_TOKEN")
    room = opts[:room] || System.get_env("STEM_ROOM_CODE")

    cond do
      not is_binary(room) or String.trim(room) == "" or not is_binary(token) or
          String.trim(token) == "" ->
        Mix.raise("""
        Missing room code or host token.

        Create a room on the site, then run the command shown to the host:

            ./script/worker --room ABC123 --token YOUR_HOST_TOKEN
        """)

      not DemucsStemAdapter.available?() ->
        Mix.raise("Demucs is not installed. Run ./script/setup first.")

      true ->
        room = room |> String.trim() |> String.upcase()
        Mix.shell().info("Waiting for songs in room #{room} on #{url}")
        loop(String.trim_trailing(url, "/"), String.trim(token), room)
    end
  end

  defp loop(url, token, room) do
    case claim(url, token, room) do
      :empty ->
        Process.sleep(@poll_ms)
        loop(url, token, room)

      {:ok, job} ->
        process_job(url, token, room, job)
        loop(url, token, room)

      {:error, reason} ->
        Mix.shell().error("Worker request failed: #{inspect(reason)}")
        Process.sleep(5_000)
        loop(url, token, room)
    end
  end

  defp claim(url, token, room) do
    case req(url, token, room) |> Req.post(url: "/internal/stems/claim") do
      {:ok, %{status: 204}} ->
        :empty

      {:ok, %{status: 200, body: body}} ->
        {:ok, job_from_body(body)}

      {:ok, %{status: 401}} ->
        {:error, :unauthorized}

      {:ok, %{status: status}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp process_job(url, token, room, job) do
    Mix.shell().info("Removing vocals: #{job.title} (##{job.id})")

    tmp_dir =
      Path.join(System.tmp_dir!(), "stem-worker-#{job.id}-#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)

    try do
      with {:ok, input} <- download_original(url, token, room, job, tmp_dir),
           {:ok, produced} <- isolate(url, token, room, job.id, input),
           :ok <- upload_instrumental(url, token, room, job.id, produced) do
        Mix.shell().info("Uploaded instrumental for ##{job.id}")
        :ok
      else
        {:error, reason} ->
          Mix.shell().error("Job ##{job.id} failed: #{inspect(reason)}")
          _ = fail(url, token, room, job.id, reason)
          :ok
      end
    after
      File.rm_rf(tmp_dir)
    end
  end

  defp download_original(url, token, room, job, tmp_dir) do
    path = job.original_path
    ext = download_ext(path)
    dest = Path.join(tmp_dir, "original#{ext}")

    request = download_req(url, token, room, path)

    case Req.get(request,
           url: path,
           into: File.stream!(dest),
           receive_timeout: @http_timeout
         ) do
      {:ok, %{status: 200}} ->
        {:ok, dest}

      {:ok, %{status: status}} ->
        File.rm(dest)
        {:error, {:http, status}}

      {:error, reason} ->
        File.rm(dest)
        {:error, reason}
    end
  end

  defp download_ext(path) do
    file_path =
      case URI.parse(path) do
        %URI{path: uri_path} when is_binary(uri_path) -> uri_path
        _ -> path
      end

    ext = file_path |> Path.extname() |> String.downcase()
    if ext == "", do: ".mp3", else: ext
  end

  defp download_req(url, token, room, path) do
    if http_url?(path) do
      Req.new(retry: false, receive_timeout: @http_timeout)
    else
      req(url, token, room)
    end
  end

  defp http_url?(path) when is_binary(path) do
    case URI.parse(path) do
      %URI{scheme: scheme} when scheme in ["http", "https"] -> true
      _ -> false
    end
  end

  defp isolate(url, token, room, song_id, input) do
    progress = fn pct ->
      _ =
        req(url, token, room)
        |> Req.post(url: "/internal/stems/#{song_id}/progress", json: %{percent: pct})

      :ok
    end

    DemucsStemAdapter.isolate(input, progress)
  end

  defp upload_instrumental(url, token, room, song_id, path) do
    filename = Path.basename(path)
    body = File.read!(path)

    case req(url, token, room)
         |> Req.post(
           url: "/internal/stems/#{song_id}/complete",
           form_multipart: [
             instrumental: {body, filename: filename}
           ],
           receive_timeout: @http_timeout
         ) do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: 409}} -> :ok
      {:ok, %{status: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fail(url, token, room, song_id, reason) do
    req(url, token, room)
    |> Req.post(url: "/internal/stems/#{song_id}/fail", json: %{reason: fail_reason(reason)})
  end

  defp fail_reason(:not_installed), do: "not_installed"
  defp fail_reason(:missing_numpy), do: "missing_numpy"
  defp fail_reason(:missing_ffmpeg), do: "missing_ffmpeg"
  defp fail_reason(:missing_audio), do: "missing_audio"
  defp fail_reason(_), do: "stem_failed"

  defp job_from_body(%{"id" => id, "title" => title, "original_path" => path}) do
    %{id: id, title: title, original_path: path}
  end

  defp req(url, token, room) do
    Req.new(
      base_url: url,
      auth: {:bearer, token},
      params: [code: room],
      decode_body: true,
      retry: false,
      receive_timeout: 30_000
    )
  end
end
