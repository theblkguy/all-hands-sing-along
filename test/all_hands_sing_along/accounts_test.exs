# test/all_hands_sing_along/accounts_test.exs
defmodule AllHandsSingAlong.AccountsTest do
  use AllHandsSingAlong.DataCase

  alias AllHandsSingAlong.Accounts
  alias AllHandsSingAlong.Fixtures

  @claims %{
    "sub" => "google-ada",
    "email" => "ada@acme.com",
    "name" => "Ada Lovelace",
    "picture" => "https://lh3.example/ada.png",
    "hd" => "acme.com"
  }

  test "upsert_from_google/1 does not set a username" do
    assert {:ok, user} = Accounts.upsert_from_google(@claims)
    assert user.username == nil
    refute AllHandsSingAlong.Accounts.User.username?(user)
  end

  test "update_username/2 requires letters, numbers, underscore" do
    user = Fixtures.user_fixture(username: nil)
    assert {:error, changeset} = Accounts.update_username(user, %{username: "a"})
    assert %{username: _} = errors_on(changeset)

    assert {:error, changeset} = Accounts.update_username(user, %{username: "Ada Lovelace"})
    assert %{username: _} = errors_on(changeset)

    assert {:ok, user} = Accounts.update_username(user, %{username: "Ada_1"})
    assert user.username == "Ada_1"
  end

  test "update_username/2 is unique case-insensitively" do
    _first = Fixtures.user_fixture(username: "Ada")
    other = Fixtures.user_fixture(username: nil)

    assert {:error, changeset} = Accounts.update_username(other, %{username: "ada"})
    assert %{username: ["has already been taken"]} = errors_on(changeset)
  end

  test "update_username/2 lets a user keep or recase their own name" do
    user = Fixtures.user_fixture(username: "Ada")
    assert {:ok, user} = Accounts.update_username(user, %{username: "Ada"})
    assert {:ok, user} = Accounts.update_username(user, %{username: "ada"})
    assert user.username == "ada"
  end
end
