defmodule AllHandsSingAlong.Catalog.UploadsTest do
  use ExUnit.Case, async: false

  alias AllHandsSingAlong.Catalog.Uploads

  setup do
    original = Application.get_env(:all_hands_sing_along, :uploads_path)

    on_exit(fn ->
      if original do
        Application.put_env(:all_hands_sing_along, :uploads_path, original)
      else
        Application.delete_env(:all_hands_sing_along, :uploads_path)
      end
    end)

    :ok
  end

  test "dir/0 defaults to priv/static/uploads" do
    Application.delete_env(:all_hands_sing_along, :uploads_path)

    assert Uploads.dir() ==
             Path.join([:code.priv_dir(:all_hands_sing_along), "static", "uploads"])
  end

  test "dir/0 uses the configured uploads_path" do
    tmp = Path.join(System.tmp_dir!(), "ahsa-uploads-#{System.unique_integer([:positive])}")
    Application.put_env(:all_hands_sing_along, :uploads_path, tmp)
    assert Uploads.dir() == tmp
  end

  test "local_path/1 rejects traversal and joins a safe name" do
    tmp = Path.join(System.tmp_dir!(), "ahsa-uploads-#{System.unique_integer([:positive])}")
    Application.put_env(:all_hands_sing_along, :uploads_path, tmp)

    assert Uploads.local_path("/uploads/track.mp3") == Path.join(tmp, "track.mp3")
    assert Uploads.local_path("/uploads/../secret.mp3") == nil
    assert Uploads.local_path("/uploads/foo/bar.mp3") == nil
    assert Uploads.local_path("/uploads/") == nil
  end
end
