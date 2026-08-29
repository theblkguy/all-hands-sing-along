defmodule Mix.Tasks.Stems.Worker do
  @moduledoc """
  Pulls vocal-isolation jobs from the hosted site and runs Demucs on this Mac.

      mix stems.worker
      mix stems.worker --url https://all-hands-sing-along.fly.dev

  Set `STEM_WORKER_TOKEN` to the same value as the Fly secret.
  """
  use Mix.Task

  alias AllHandsSingAlong.Catalog.DemucsStemAdapter

  @shortdoc "Run Demucs for songs uploaded to the hosted karaoke site"

  @default_url "https://all-hands-sing-along.fly.dev"
  @poll_ms 2_000
  @http_timeout 180_000

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:req)

    {opts, _rest} =
      OptionParser.parse!(args, strict: [url: :string, token: :string], aliases: [u: :url])

    url = opts[:url] || System.get_env("STEM_SITE_URL") || @default_url
    token = opts[:token] || System.get_env("STEM_WORKER_TOKEN")

    cond do
      not is_binary(token) or String.trim(token) == "" ->
        Mix.raise("Set STEM_WORKER_TOKEN to the Fly secret of the same name")

      not DemucsStemAdapter.available?() ->
        Mix.raise("Demucs is not installed on this Mac. See README: Install vocal isolation")

      true ->
        Mix.shell().info("Waiting for songs on #{url}")
        loop(String.trim_trailing(url, "/"), String.trim(token))
    end
  end

  defp loop(url, token) do
    case claim(url, token) do
      :empty ->
        Process.sleep(@poll_ms)
        loop(url, token)

      {:ok, job} ->
        process_job(url, token, job)
        loop(url, token)

      {:error, reason} ->
        Mix.shell().error("Worker request failed: #{inspect(reason)}")
        Process.sleep(5_000)
        loop(url, token)
    end
  end

  defp claim(url, token) do
    case req(url, token) |> Req.post(url: "/internal/stems/claim") do
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

  defp process_job(url, token, job) do
    Mix.shell().info("Removing vocals: #{job.title} (##{job.id})")

    tmp_dir =
      Path.join(System.tmp_dir!(), "stem-worker-#{job.id}-#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)

    try do
      with {:ok, input} <- download_original(url, token, job, tmp_dir),
           {:ok, produced} <- isolate(url, token, job.id, input),
           :ok <- upload_instrumental(url, token, job.id, produced) do
        Mix.shell().info("Uploaded instrumental for ##{job.id}")
        :ok
      else
        {:error, reason} ->
          Mix.shell().error("Job ##{job.id} failed: #{inspect(reason)}")
          _ = fail(url, token, job.id, reason)
          :ok
      end
    after
      File.rm_rf(tmp_dir)
    end
  end

  defp download_original(url, token, job, tmp_dir) do
    ext = job.original_path |> Path.extname() |> String.downcase()
    ext = if ext == "", do: ".mp3", else: ext
    dest = Path.join(tmp_dir, "original#{ext}")

    case req(url, token)
         |> Req.get(
           url: job.original_path,
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

  defp isolate(url, token, song_id, input) do
    progress = fn pct ->
      _ =
        req(url, token)
        |> Req.post(url: "/internal/stems/#{song_id}/progress", json: %{percent: pct})

      :ok
    end

    DemucsStemAdapter.isolate(input, progress)
  end

  defp upload_instrumental(url, token, song_id, path) do
    filename = Path.basename(path)
    body = File.read!(path)

    case req(url, token)
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

  defp fail(url, token, song_id, reason) do
    req(url, token)
    |> Req.post(url: "/internal/stems/#{song_id}/fail", json: %{reason: fail_reason(reason)})
  end

  defp fail_reason(:not_installed), do: "not_installed"
  defp fail_reason(:missing_numpy), do: "missing_numpy"
  defp fail_reason(:missing_audio), do: "missing_audio"
  defp fail_reason(_), do: "stem_failed"

  defp job_from_body(%{"id" => id, "title" => title, "original_path" => path}) do
    %{id: id, title: title, original_path: path}
  end

  defp req(url, token) do
    Req.new(
      base_url: url,
      auth: {:bearer, token},
      decode_body: true,
      retry: false,
      receive_timeout: 30_000
    )
  end
end
