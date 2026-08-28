# lib/all_hands_sing_along/uploads.ex
defmodule AllHandsSingAlong.Uploads do
  @moduledoc """
  Persist LiveView uploads under priv/static/uploads.
  """

  @allowed_audio ~w(.mp3 .wav .m4a .ogg .aac)
  @allowed_lyrics ~w(.lrc .txt)

  @spec dir() :: String.t()
  def dir do
    Path.join(:code.priv_dir(:all_hands_sing_along), "static/uploads")
  end

  @spec allowed_audio_ext?(String.t()) :: boolean()
  def allowed_audio_ext?(ext) when is_binary(ext) do
    String.downcase(ext) in @allowed_audio
  end

  @spec allowed_lyrics_ext?(String.t()) :: boolean()
  def allowed_lyrics_ext?(ext) when is_binary(ext) do
    String.downcase(ext) in @allowed_lyrics
  end

  @spec store_audio(String.t(), String.t()) :: {:ok, String.t()} | {:error, :invalid_ext}
  def store_audio(tmp_path, client_name) when is_binary(tmp_path) and is_binary(client_name) do
    ext = client_name |> Path.extname() |> String.downcase()

    if allowed_audio_ext?(ext) do
      File.mkdir_p!(dir())
      dest_name = Ecto.UUID.generate() <> ext
      dest = Path.join(dir(), dest_name)
      File.cp!(tmp_path, dest)
      {:ok, "/uploads/#{dest_name}"}
    else
      {:error, :invalid_ext}
    end
  end

  @spec read_lyrics(String.t(), String.t()) :: {:ok, String.t()} | {:error, :invalid_ext}
  def read_lyrics(tmp_path, client_name) when is_binary(tmp_path) and is_binary(client_name) do
    ext = client_name |> Path.extname() |> String.downcase()

    if allowed_lyrics_ext?(ext) do
      {:ok, File.read!(tmp_path)}
    else
      {:error, :invalid_ext}
    end
  end
end
