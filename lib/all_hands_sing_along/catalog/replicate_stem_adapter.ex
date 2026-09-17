# lib/all_hands_sing_along/catalog/replicate_stem_adapter.ex
defmodule AllHandsSingAlong.Catalog.ReplicateStemAdapter do
  @moduledoc """
  Runs Demucs on Replicate's GPUs instead of the host's Mac.

  The Fly VM only does HTTP and a tiny ffmpeg mix, so nobody has to install
  anything. Set `REPLICATE_API_TOKEN` and the app picks this adapter up
  automatically (see config/runtime.exs).

  Flow: hand Replicate a URL to the original (a presigned Tigris URL in prod,
  or an upload to Replicate's Files API when we only have a local path), poll
  the prediction, download `vocals` + `no_vocals`, mix a quiet guide vocal
  with ffmpeg, and return the produced file for `Uploads.store_audio!/2`.
  """

  @behaviour AllHandsSingAlong.Catalog.StemAdapter

  require Logger

  alias AllHandsSingAlong.Catalog.DemucsStemAdapter

  @api "https://api.replicate.com/v1"
  # ryan5453/demucs — htdemucs, two_stems, returns %{"stems" => [%{"name", "audio"}]}
  @default_version "b26a4313b4d75983d60657f80dfa93b9beb354f6e4fa29ecd27ffe14d60117f6"
  @poll_ms 2_500
  @max_wait_ms 15 * 60_000

  @impl true
  def available? do
    is_binary(token()) and token() != ""
  end

  @impl true
  def isolate(input_path, progress) when is_binary(input_path) do
    with {:ok, url} <- upload_to_replicate(input_path) do
      isolate_url(url, progress)
    end
  end

  @impl true
  def isolate_url(audio_url, progress) when is_binary(audio_url) do
    tmp = Path.join(System.tmp_dir!(), "replicate-stems-" <> Ecto.UUID.generate())

    with :ok <- File.mkdir_p(tmp),
         _ <- report(progress, 5),
         {:ok, prediction} <- create_prediction(audio_url),
         _ <- report(progress, 15),
         {:ok, output} <- await_prediction(prediction, progress),
         {:ok, %{vocals: vocals_url, no_vocals: instrumental_url}} <- pick_stems(output),
         _ <- report(progress, 85),
         {:ok, instrumental} <- download(instrumental_url, Path.join(tmp, "no_vocals.mp3")),
         {:ok, vocals} <- download(vocals_url, Path.join(tmp, "vocals.mp3")),
         _ <- report(progress, 92),
         {:ok, produced} <- mix_or_fallback(instrumental, vocals, Path.join(tmp, "guide.mp3")) do
      report(progress, 100)
      {:ok, produced}
    else
      {:error, reason} = error ->
        File.rm_rf(tmp)
        Logger.warning("replicate demucs failed: #{inspect(reason)}")
        error

      other ->
        File.rm_rf(tmp)
        Logger.warning("replicate demucs failed: #{inspect(other)}")
        {:error, :stem_failed}
    end
  end

  # -- Replicate API ---------------------------------------------------------

  defp create_prediction(audio_url) do
    body = %{
      version: version(),
      input: %{
        audio: audio_url,
        model: model(),
        two_stems: "vocals",
        output_format: "mp3"
      }
    }

    case Req.post(req(), url: "/predictions", json: body) do
      {:ok, %{status: status, body: %{"id" => _} = prediction}} when status in 200..299 ->
        {:ok, prediction}

      {:ok, %{status: 401}} ->
        {:error, :replicate_unauthorized}

      {:ok, %{status: 402}} ->
        {:error, :replicate_billing}

      {:ok, %{status: status, body: body}} ->
        Logger.warning(
          "replicate create failed #{status}: #{inspect(body) |> String.slice(0, 300)}"
        )

        {:error, :stem_failed}

      {:error, reason} ->
        {:error, {:http, reason}}
    end
  end

  defp await_prediction(%{"id" => id} = prediction, progress) do
    deadline = System.monotonic_time(:millisecond) + @max_wait_ms
    poll(id, prediction, progress, deadline)
  end

  defp poll(id, prediction, progress, deadline) do
    case prediction do
      %{"status" => "succeeded", "output" => output} ->
        {:ok, output}

      %{"status" => "failed"} = failed ->
        Logger.warning("replicate prediction failed: #{inspect(failed["error"])}")
        {:error, :stem_failed}

      %{"status" => "canceled"} ->
        {:error, :stem_failed}

      %{"status" => status} ->
        if System.monotonic_time(:millisecond) > deadline do
          _ = Req.post(req(), url: "/predictions/#{id}/cancel")
          {:error, :timeout}
        else
          if status == "processing", do: report(progress, 40)
          Process.sleep(@poll_ms)

          case Req.get(req(), url: "/predictions/#{id}") do
            {:ok, %{status: 200, body: %{"status" => _} = fresh}} ->
              poll(id, fresh, progress, deadline)

            {:ok, %{status: status}} ->
              {:error, {:http, status}}

            {:error, reason} ->
              {:error, {:http, reason}}
          end
        end
    end
  end

  # ryan5453/demucs: %{"stems" => [%{"name" => "vocals", "audio" => url}, ...]}
  # Also tolerate a plain name=>url map or a bare list of URLs.
  defp pick_stems(%{"stems" => stems}) when is_list(stems) do
    stems
    |> Enum.reduce(%{}, fn
      %{"name" => name, "audio" => url}, acc when is_binary(url) -> Map.put(acc, name, url)
      _, acc -> acc
    end)
    |> pick_stems()
  end

  defp pick_stems(%{} = map) when not is_map_key(map, "stems") do
    vocals = map["vocals"]
    instrumental = map["no_vocals"] || map["instrumental"] || map["accompaniment"]

    if is_binary(vocals) and is_binary(instrumental) do
      {:ok, %{vocals: vocals, no_vocals: instrumental}}
    else
      {:error, :no_output}
    end
  end

  defp pick_stems(list) when is_list(list) do
    list
    |> Enum.filter(&is_binary/1)
    |> Map.new(fn url ->
      name =
        url |> URI.parse() |> Map.get(:path) |> to_string() |> Path.basename() |> Path.rootname()

      {name, url}
    end)
    |> pick_stems()
  end

  defp pick_stems(_), do: {:error, :no_output}

  defp download(url, dest) do
    case Req.get(url, receive_timeout: 120_000, retry: false, into: File.stream!(dest)) do
      {:ok, %{status: status}} when status in 200..299 ->
        if File.regular?(dest) and File.stat!(dest).size > 0,
          do: {:ok, dest},
          else: {:error, :no_output}

      {:ok, %{status: status}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, {:http, reason}}
    end
  end

  # Replicate's Files API gives us a fetchable URL for a local file. Used in
  # dev (local uploads adapter) and as a fallback if a presigned URL is missing.
  defp upload_to_replicate(path) do
    form = [content: {File.stream!(path, 1_048_576), filename: Path.basename(path)}]

    case Req.post(req(), url: "/files", form_multipart: form, receive_timeout: 180_000) do
      {:ok, %{status: status, body: %{"urls" => %{"get" => url}}}}
      when status in 200..299 and is_binary(url) ->
        {:ok, url}

      {:ok, %{status: status, body: body}} ->
        Logger.warning(
          "replicate file upload failed #{status}: #{inspect(body) |> String.slice(0, 300)}"
        )

        {:error, :stem_failed}

      {:error, reason} ->
        {:error, {:http, reason}}
    end
  end

  # -- Guide vocal ----------------------------------------------------------

  # Reuse the same ffmpeg mix the Mac path uses, so the result sounds identical
  # regardless of where Demucs ran. If ffmpeg is missing on the server, ship the
  # plain instrumental rather than failing the song.
  defp mix_or_fallback(instrumental, vocals, output) do
    case DemucsStemAdapter.mix_guide_vocal(instrumental, vocals, output) do
      {:ok, produced} ->
        File.rm(instrumental)
        File.rm(vocals)
        {:ok, produced}

      {:error, :missing_ffmpeg} ->
        Logger.warning("ffmpeg missing on server; using plain instrumental without guide vocal")
        {:ok, instrumental}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # -- Config ---------------------------------------------------------------

  defp req do
    Req.new(
      base_url: @api,
      auth: {:bearer, token()},
      receive_timeout: 60_000,
      retry: :transient
    )
  end

  defp report(progress, pct) when is_function(progress, 1), do: progress.(pct)
  defp report(_, _), do: :ok

  defp token, do: config()[:token] || System.get_env("REPLICATE_API_TOKEN")
  defp version, do: config()[:version] || @default_version
  defp model, do: config()[:model] || "htdemucs"

  defp config do
    Application.get_env(:all_hands_sing_along, __MODULE__, [])
  end
end
