# lib/all_hands_sing_along/catalog/lyrics.ex
defmodule AllHandsSingAlong.Catalog.Lyrics do
  @moduledoc """
  Fetch synced LRC from LRCLIB using title and artist.
  """

  @user_agent "AllHandsSingAlong/0.1.0 (karaoke companion)"
  @get_url "https://lrclib.net/api/get"
  @search_url "https://lrclib.net/api/search"

  @type hit :: %{
          id: integer(),
          track_name: String.t(),
          artist_name: String.t(),
          album_name: String.t() | nil,
          duration_s: number() | nil
        }

  @spec fetch(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def fetch(artist, title) when is_binary(artist) and is_binary(title) do
    artist = String.trim(artist)
    title = String.trim(title)

    if artist == "" or title == "" do
      {:error, :invalid}
    else
      get(artist_name: artist, track_name: title)
    end
  end

  def fetch(_, _), do: {:error, :invalid}

  @spec resolve(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def resolve(artist, title) when is_binary(artist) and is_binary(title) do
    case fetch(artist, title) do
      {:ok, lrc} ->
        {:ok, lrc}

      {:error, _} ->
        case search(artist, title) do
          {:ok, hits} -> pick_best(hits, artist, title)
          error -> error
        end
    end
  end

  def resolve(_, _), do: {:error, :invalid}

  @spec search(String.t(), String.t()) :: {:ok, [hit()]} | {:error, term()}
  def search(artist, title) when is_binary(artist) and is_binary(title) do
    artist = String.trim(artist)
    title = String.trim(title)

    if artist == "" or title == "" do
      {:error, :invalid}
    else
      url = config()[:search_url] || @search_url

      case request(url, artist_name: artist, track_name: title) do
        {:ok, %Req.Response{status: 200, body: body}} when is_list(body) ->
          {:ok, Enum.map(body, &normalize_hit/1) |> Enum.reject(&is_nil/1)}

        {:ok, %Req.Response{status: 404}} ->
          {:ok, []}

        {:ok, %Req.Response{status: status}} ->
          {:error, {:http, status}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def search(_, _), do: {:error, :invalid}

  @spec fetch_by_id(integer() | String.t()) :: {:ok, String.t()} | {:error, term()}
  def fetch_by_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> fetch_by_id(int)
      _ -> {:error, :invalid}
    end
  end

  def fetch_by_id(id) when is_integer(id) and id > 0 do
    get_url((config()[:url] || @get_url) <> "/" <> Integer.to_string(id), [])
  end

  def fetch_by_id(_), do: {:error, :invalid}

  defp pick_best([], _artist, _title), do: {:error, :not_found}

  defp pick_best(hits, artist, title) do
    wanted_title = normalize_name(title)
    wanted_artist = normalize_name(artist)

    exact =
      Enum.filter(hits, fn hit ->
        normalize_name(hit.track_name) == wanted_title and
          normalize_name(hit.artist_name) == wanted_artist
      end)

    candidates =
      case exact do
        [] -> hits
        matches -> matches
      end

    case candidates do
      [hit] -> fetch_by_id(hit.id)
      _ -> {:error, :ambiguous}
    end
  end

  defp get(params) do
    get_url(config()[:url] || @get_url, params)
  end

  defp get_url(url, params) do
    case request(url, params) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        synced(body)

      {:ok, %Req.Response{status: 404}} ->
        {:error, :not_found}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp request(url, params) do
    opts =
      [
        params: params,
        headers: [{"user-agent", @user_agent}],
        receive_timeout: 8_000
      ]
      |> Keyword.merge(config()[:req_options] || [])

    Req.get(url, opts)
  end

  defp synced(%{"syncedLyrics" => lrc}) when is_binary(lrc) do
    if String.trim(lrc) == "", do: {:error, :no_synced_lyrics}, else: {:ok, lrc}
  end

  defp synced(_), do: {:error, :no_synced_lyrics}

  defp normalize_hit(hit) when is_map(hit) do
    id = hit["id"] || hit[:id]
    track = hit["trackName"] || hit["name"] || hit[:track_name]
    artist = hit["artistName"] || hit[:artist_name]

    if is_integer(id) and is_binary(track) and is_binary(artist) do
      %{
        id: id,
        track_name: track,
        artist_name: artist,
        album_name: hit["albumName"] || hit[:album_name],
        duration_s: hit["duration"] || hit[:duration]
      }
    else
      nil
    end
  end

  defp normalize_hit(_), do: nil

  defp normalize_name(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, " ")
    |> String.trim()
  end

  defp config do
    Application.get_env(:all_hands_sing_along, __MODULE__, [])
  end
end
