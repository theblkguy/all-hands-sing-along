# lib/all_hands_sing_along/catalog/uploads.ex
defmodule AllHandsSingAlong.Catalog.Uploads do
  @moduledoc """
  Persist guest audio. Local disk in dev/test; Tigris object storage in prod.
  Logical paths stay `/uploads/<uuid>.ext`.
  """

  alias AllHandsSingAlong.Catalog.Uploads.Local

  @audio_exts MapSet.new([".mp3", ".wav", ".m4a", ".ogg"])
  @audio_accept ~w(.mp3 .wav .m4a .ogg audio/mpeg audio/wav audio/mp4 audio/ogg)
  @lrc_accept ~w(.lrc)
  @max_audio_bytes 32_000_000
  @max_lrc_bytes 200_000
  @max_audio_files_per_room 20

  @spec audio_accept() :: [String.t()]
  def audio_accept, do: @audio_accept

  @spec lrc_accept() :: [String.t()]
  def lrc_accept, do: @lrc_accept

  @spec max_audio_bytes() :: pos_integer()
  def max_audio_bytes, do: @max_audio_bytes

  @spec max_lrc_bytes() :: pos_integer()
  def max_lrc_bytes, do: @max_lrc_bytes

  @spec max_audio_files_per_room() :: pos_integer()
  def max_audio_files_per_room, do: @max_audio_files_per_room

  @spec adapter() :: module()
  def adapter do
    config()[:adapter] || Local
  end

  @spec dir() :: String.t() | nil
  def dir, do: adapter().dir()

  @spec ensure_dir!() :: :ok
  def ensure_dir!, do: adapter().ensure_dir!()

  @spec audio_ext?(String.t()) :: boolean()
  def audio_ext?(ext) when is_binary(ext) do
    MapSet.member?(@audio_exts, String.downcase(ext))
  end

  @spec safe_name?(String.t()) :: boolean()
  def safe_name?(name) do
    name != "" and not String.contains?(name, "/") and not String.contains?(name, "\\") and
      not String.contains?(name, "..")
  end

  @spec local_path(String.t() | nil) :: String.t() | nil
  def local_path(path), do: adapter().local_path(path)

  @spec store_audio!(String.t(), String.t()) ::
          {:ok, String.t()} | {:error, :invalid_ext | term()}
  def store_audio!(source_path, client_name)
      when is_binary(source_path) and is_binary(client_name) do
    ext = client_name |> Path.extname() |> String.downcase()

    if audio_ext?(ext) do
      adapter().put(source_path, Ecto.UUID.generate() <> ext)
    else
      {:error, :invalid_ext}
    end
  end

  @spec public_url(String.t() | nil) :: String.t() | nil
  def public_url(nil), do: nil
  def public_url(path) when is_binary(path), do: adapter().public_url(path)

  @spec serve(String.t()) :: {:file, String.t()} | {:redirect, String.t()} | :not_found
  def serve(path) when is_binary(path), do: adapter().serve(path)

  @spec read_text!(String.t()) :: String.t()
  def read_text!(path) when is_binary(path) do
    File.read!(path)
  end

  defp config do
    Application.get_env(:all_hands_sing_along, __MODULE__, [])
  end
end
