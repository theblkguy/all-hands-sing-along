# lib/all_hands_sing_along/catalog/uploads/tigris.ex
defmodule AllHandsSingAlong.Catalog.Uploads.Tigris do
  @moduledoc false

  require Logger

  alias AllHandsSingAlong.Catalog.Uploads

  @expires_s 3600

  def dir, do: nil

  def ensure_dir!, do: :ok

  def local_path("/audio/" <> name) when is_binary(name) do
    if Uploads.safe_name?(name) do
      Path.join([:code.priv_dir(:all_hands_sing_along), "static", "audio", name])
    end
  end

  def local_path(_), do: nil

  def put(source_path, filename) do
    key = object_key(filename)
    body = File.read!(source_path)
    content_type = MIME.from_path(filename)

    case request(:put, key, body, content_type) do
      {:ok, %{status: status}} when status in 200..299 ->
        {:ok, "/uploads/" <> filename}

      {:ok, %{status: status}} ->
        Logger.error("tigris put failed: #{status}")
        {:error, :store_failed}

      {:error, reason} ->
        Logger.error("tigris put failed: #{inspect(reason)}")
        {:error, :store_failed}
    end
  end

  def public_url("/uploads/" <> name) do
    if Uploads.safe_name?(name), do: presign_get(object_key(name))
  end

  def public_url(path) when is_binary(path), do: path

  def serve("/uploads/" <> name) do
    case public_url("/uploads/" <> name) do
      url when is_binary(url) -> {:redirect, url}
      _ -> :not_found
    end
  end

  def serve(_), do: :not_found

  defp object_key(filename), do: "uploads/" <> filename

  defp request(method, key, body, content_type) do
    %{url: url, headers: headers} = signed_request(method, key, body, content_type)

    opts =
      [
        headers: headers,
        body: body,
        retry: false,
        receive_timeout: 60_000
      ]
      |> Keyword.merge(config()[:req_options] || [])

    Req.request([method: method, url: url] ++ opts)
  end

  defp presign_get(key) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    amz_date = Calendar.strftime(now, "%Y%m%dT%H%M%SZ")
    datestamp = Calendar.strftime(now, "%Y%m%d")
    creds = credential(datestamp)
    host = host()
    path = "/" <> bucket() <> "/" <> key

    query =
      %{
        "X-Amz-Algorithm" => "AWS4-HMAC-SHA256",
        "X-Amz-Credential" => creds,
        "X-Amz-Date" => amz_date,
        "X-Amz-Expires" => Integer.to_string(@expires_s),
        "X-Amz-SignedHeaders" => "host"
      }

    canonical_query = canonical_query(query)
    payload_hash = "UNSIGNED-PAYLOAD"

    canonical =
      [
        "GET",
        path,
        canonical_query,
        "host:#{host}",
        "",
        "host",
        payload_hash
      ]
      |> Enum.join("\n")

    signature = signature(datestamp, amz_date, canonical)
    endpoint() <> path <> "?" <> canonical_query <> "&X-Amz-Signature=" <> signature
  end

  defp signed_request(method, key, body, content_type) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    amz_date = Calendar.strftime(now, "%Y%m%dT%H%M%SZ")
    datestamp = Calendar.strftime(now, "%Y%m%d")
    host = host()
    path = "/" <> bucket() <> "/" <> key
    payload_hash = sha256_hex(body)
    method_s = method |> Atom.to_string() |> String.upcase()

    canonical_headers =
      [
        "content-type:#{content_type}",
        "host:#{host}",
        "x-amz-content-sha256:#{payload_hash}",
        "x-amz-date:#{amz_date}"
      ]
      |> Enum.join("\n")

    signed_headers = "content-type;host;x-amz-content-sha256;x-amz-date"

    canonical =
      [
        method_s,
        path,
        "",
        canonical_headers,
        "",
        signed_headers,
        payload_hash
      ]
      |> Enum.join("\n")

    sig = signature(datestamp, amz_date, canonical)

    auth =
      "AWS4-HMAC-SHA256 Credential=#{credential(datestamp)}, SignedHeaders=#{signed_headers}, Signature=#{sig}"

    %{
      url: endpoint() <> path,
      headers: [
        {"content-type", content_type},
        {"host", host},
        {"x-amz-content-sha256", payload_hash},
        {"x-amz-date", amz_date},
        {"authorization", auth}
      ]
    }
  end

  defp signature(datestamp, amz_date, canonical_request) do
    string_to_sign =
      [
        "AWS4-HMAC-SHA256",
        amz_date,
        scope(datestamp),
        sha256_hex(canonical_request)
      ]
      |> Enum.join("\n")

    datestamp
    |> signing_key()
    |> hmac(string_to_sign)
    |> Base.encode16(case: :lower)
  end

  defp signing_key(datestamp) do
    ("AWS4" <> secret())
    |> hmac(datestamp)
    |> hmac(region())
    |> hmac("s3")
    |> hmac("aws4_request")
  end

  defp credential(datestamp), do: "#{access_key()}/#{scope(datestamp)}"
  defp scope(datestamp), do: "#{datestamp}/#{region()}/s3/aws4_request"

  defp canonical_query(map) do
    map
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Enum.map(fn {k, v} -> URI.encode_www_form(k) <> "=" <> URI.encode_www_form(v) end)
    |> Enum.join("&")
  end

  defp hmac(key, data), do: :crypto.mac(:hmac, :sha256, key, data)
  defp sha256_hex(data), do: :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)

  defp config do
    Application.get_env(:all_hands_sing_along, AllHandsSingAlong.Catalog.Uploads, [])
  end

  defp endpoint do
    config()[:endpoint] |> to_string() |> String.trim_trailing("/")
  end

  defp host do
    endpoint()
    |> URI.parse()
    |> Map.get(:host)
  end

  defp bucket, do: config()[:bucket]
  defp region, do: config()[:region] || "auto"
  defp access_key, do: config()[:access_key_id]
  defp secret, do: config()[:secret_access_key]
end
