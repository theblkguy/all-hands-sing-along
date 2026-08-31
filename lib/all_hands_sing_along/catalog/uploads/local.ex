# lib/all_hands_sing_along/catalog/uploads/local.ex
defmodule AllHandsSingAlong.Catalog.Uploads.Local do
  @moduledoc false

  alias AllHandsSingAlong.Catalog.Uploads

  def dir do
    case Application.get_env(:all_hands_sing_along, :uploads_path) do
      path when is_binary(path) and path != "" -> path
      _ -> Path.join([:code.priv_dir(:all_hands_sing_along), "static", "uploads"])
    end
  end

  def ensure_dir! do
    File.mkdir_p!(dir())
    :ok
  end

  def local_path("/uploads/" <> name) when is_binary(name) do
    if Uploads.safe_name?(name), do: Path.join(dir(), name)
  end

  def local_path("/audio/" <> name) when is_binary(name) do
    if Uploads.safe_name?(name) do
      Path.join([:code.priv_dir(:all_hands_sing_along), "static", "audio", name])
    end
  end

  def local_path(_), do: nil

  def put(source_path, filename) do
    ensure_dir!()
    dest = Path.join(dir(), filename)
    File.cp!(source_path, dest)
    {:ok, "/uploads/" <> filename}
  end

  def public_url(path) when is_binary(path), do: path

  def serve("/uploads/" <> _name = logical) do
    case local_path(logical) do
      path when is_binary(path) ->
        if File.regular?(path), do: {:file, path}, else: :not_found

      _ ->
        :not_found
    end
  end

  def serve(_), do: :not_found
end
