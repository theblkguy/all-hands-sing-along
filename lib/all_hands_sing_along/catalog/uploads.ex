# lib/all_hands_sing_along/catalog/uploads.ex
defmodule AllHandsSingAlong.Catalog.Uploads do
  @moduledoc """
  Persist LiveView uploads under priv/static/uploads.
  """

  @audio_exts MapSet.new([".mp3", ".wav", ".m4a", ".ogg"])

  @spec dir() :: String.t()
  def dir do
    Path.join([:code.priv_dir(:all_hands_sing_along), "static", "uploads"])
  end

  @spec ensure_dir!() :: :ok
  def ensure_dir! do
    File.mkdir_p!(dir())
    :ok
  end

  @spec audio_ext?(String.t()) :: boolean()
  def audio_ext?(ext) when is_binary(ext) do
    MapSet.member?(@audio_exts, String.downcase(ext))
  end

  @spec local_path(String.t() | nil) :: String.t() | nil
  def local_path("/uploads/" <> name) when is_binary(name) do
    if safe_name?(name), do: Path.join(dir(), name)
  end

  def local_path("/audio/" <> name) when is_binary(name) do
    if safe_name?(name) do
      Path.join([:code.priv_dir(:all_hands_sing_along), "static", "audio", name])
    end
  end

  def local_path(_), do: nil

  @spec store_audio!(String.t(), String.t()) :: {:ok, String.t()} | {:error, :invalid_ext}
  def store_audio!(source_path, client_name)
      when is_binary(source_path) and is_binary(client_name) do
    ext = client_name |> Path.extname() |> String.downcase()

    if audio_ext?(ext) do
      ensure_dir!()
      filename = Ecto.UUID.generate() <> ext
      dest = Path.join(dir(), filename)
      File.cp!(source_path, dest)
      {:ok, "/uploads/" <> filename}
    else
      {:error, :invalid_ext}
    end
  end

  @spec read_text!(String.t()) :: String.t()
  def read_text!(path) when is_binary(path) do
    File.read!(path)
  end

  defp safe_name?(name) do
    name != "" and not String.contains?(name, "/") and not String.contains?(name, "\\") and
      not String.contains?(name, "..")
  end
end
