defmodule AllHandsSingAlong.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use AllHandsSingAlong.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias AllHandsSingAlong.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import AllHandsSingAlong.DataCase
    end
  end

  setup tags do
    AllHandsSingAlong.DataCase.setup_sandbox(tags)
    AllHandsSingAlong.DataCase.stub_lyrics_not_found()
    Application.put_env(:all_hands_sing_along, :stem_stub, :ok)
    Application.put_env(:all_hands_sing_along, :stem_available, true)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(AllHandsSingAlong.Repo, shared: not tags[:async])

    on_exit(fn ->
      AllHandsSingAlong.Rooms.Playback.stop_all()
      Ecto.Adapters.SQL.Sandbox.stop_owner(pid)
    end)
  end

  def stub_lyrics_not_found do
    Req.Test.set_req_test_to_shared()

    Req.Test.stub(AllHandsSingAlong.Catalog.Lyrics, fn conn ->
      conn
      |> Plug.Conn.put_status(404)
      |> Req.Test.json(%{"code" => 404, "message" => "Not Found"})
    end)
  end

  def stub_lyrics_http_error(status \\ 500) do
    Req.Test.set_req_test_to_shared()

    Req.Test.stub(AllHandsSingAlong.Catalog.Lyrics, fn conn ->
      conn
      |> Plug.Conn.put_status(status)
      |> Req.Test.json(%{"message" => "boom"})
    end)
  end

  def stub_lyrics_synced(lrc \\ "[00:00.00]Hello from LRCLIB") do
    Req.Test.set_req_test_to_shared()

    Req.Test.stub(AllHandsSingAlong.Catalog.Lyrics, fn conn ->
      Req.Test.json(conn, %{
        "syncedLyrics" => lrc,
        "plainLyrics" => "Hello from LRCLIB"
      })
    end)
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
