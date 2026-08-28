# test/all_hands_sing_along/catalog/lyrics_test.exs
defmodule AllHandsSingAlong.Catalog.LyricsTest do
  use AllHandsSingAlong.DataCase

  alias AllHandsSingAlong.Catalog.Lyrics

  test "fetch/2 returns synced lyrics" do
    stub_lyrics_synced("[00:12.00]Levitating")

    assert {:ok, lrc} = Lyrics.fetch("Dua Lipa", "Levitating")
    assert lrc =~ "Levitating"
  end

  test "fetch/2 returns not_found on 404" do
    stub_lyrics_not_found()
    assert {:error, :not_found} = Lyrics.fetch("Unknown Artist", "Missing Song")
  end

  test "fetch/2 rejects blank artist or title" do
    assert {:error, :invalid} = Lyrics.fetch("  ", "Levitating")
    assert {:error, :invalid} = Lyrics.fetch("Dua Lipa", "")
  end

  test "fetch/2 returns no_synced_lyrics when the payload has none" do
    Req.Test.stub(AllHandsSingAlong.Catalog.Lyrics, fn conn ->
      Req.Test.json(conn, %{"syncedLyrics" => nil, "plainLyrics" => "hello"})
    end)

    assert {:error, :no_synced_lyrics} = Lyrics.fetch("Dua Lipa", "Levitating")
  end

  test "search/2 returns catalog hits" do
    Req.Test.stub(AllHandsSingAlong.Catalog.Lyrics, fn conn ->
      Req.Test.json(conn, [
        %{
          "id" => 7,
          "trackName" => "Can You Stand the Rain",
          "artistName" => "New Edition",
          "albumName" => "Heart Break"
        }
      ])
    end)

    assert {:ok, [hit]} = Lyrics.search("New Edition", "Can You Stand the Rain")
    assert hit.id == 7
    assert hit.track_name == "Can You Stand the Rain"
    assert hit.artist_name == "New Edition"
  end

  test "resolve/2 uses a unique search hit when get misses" do
    Req.Test.stub(AllHandsSingAlong.Catalog.Lyrics, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)

      cond do
        String.ends_with?(conn.request_path, "/search") ->
          Req.Test.json(conn, [
            %{
              "id" => 9,
              "trackName" => "If It Isn't Love",
              "artistName" => "New Edition"
            }
          ])

        String.ends_with?(conn.request_path, "/get/9") ->
          Req.Test.json(conn, %{"syncedLyrics" => "[00:05.00]I think it's time"})

        true ->
          conn
          |> Plug.Conn.put_status(404)
          |> Req.Test.json(%{"message" => "Not Found"})
      end
    end)

    assert {:ok, lrc} = Lyrics.resolve("New Edition", "If It Isn't Love")
    assert lrc =~ "I think it's time"
  end

  test "fetch_by_id/1 requests GET /api/get/:id" do
    Req.Test.stub(AllHandsSingAlong.Catalog.Lyrics, fn conn ->
      assert String.ends_with?(conn.request_path, "/get/3396226")
      refute Map.has_key?(Plug.Conn.fetch_query_params(conn).query_params, "id")
      Req.Test.json(conn, %{"syncedLyrics" => "[00:01.00]Hi"})
    end)

    assert {:ok, lrc} = Lyrics.fetch_by_id(3_396_226)
    assert lrc =~ "Hi"
  end
end
