# lib/all_hands_sing_along/accounts.ex
defmodule AllHandsSingAlong.Accounts do
  @moduledoc """
  Users who sign in with Google.
  """
  import Ecto.Query

  alias AllHandsSingAlong.Accounts.User
  alias AllHandsSingAlong.Repo

  @spec get_user(integer() | String.t() | nil) :: User.t() | nil
  def get_user(id) when is_integer(id), do: Repo.get(User, id)

  def get_user(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> get_user(int)
      _ -> nil
    end
  end

  def get_user(_), do: nil

  @doc """
  Create or refresh a user from a Google userinfo/ID-token payload.
  Keyed on `sub`, so a renamed account or changed email keeps its rooms.
  Does not set or overwrite `username`.
  """
  @spec upsert_from_google(map()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t() | :invalid_claims}
  def upsert_from_google(%{"sub" => sub} = claims) when is_binary(sub) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs = %{
      google_sub: sub,
      email: claims["email"],
      name: claims["name"] || claims["given_name"] || claims["email"],
      avatar_url: claims["picture"],
      hosted_domain: claims["hd"],
      last_signed_in_at: now
    }

    case Repo.get_by(User, google_sub: sub) do
      nil -> %User{} |> User.changeset(attrs) |> Repo.insert()
      user -> user |> User.changeset(attrs) |> Repo.update()
    end
  end

  def upsert_from_google(_), do: {:error, :invalid_claims}

  @spec change_username(User.t(), map()) :: Ecto.Changeset.t()
  def change_username(%User{} = user, attrs \\ %{}) do
    User.username_changeset(user, unwrap(attrs))
  end

  @spec update_username(User.t(), map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_username(%User{} = user, attrs) when is_map(attrs) do
    changeset =
      user
      |> User.username_changeset(unwrap(attrs))
      |> validate_username_available()

    Repo.update(changeset)
  end

  defp validate_username_available(changeset) do
    username = Ecto.Changeset.get_change(changeset, :username)
    user_id = changeset.data.id

    cond do
      not is_binary(username) ->
        changeset

      username_taken?(username, user_id) ->
        Ecto.Changeset.add_error(changeset, :username, "has already been taken")

      true ->
        changeset
    end
  end

  defp username_taken?(username, user_id) do
    lowered = String.downcase(username)

    User
    |> where([u], fragment("lower(?) = ?", u.username, ^lowered))
    |> then(fn query ->
      if is_integer(user_id) do
        where(query, [u], u.id != ^user_id)
      else
        query
      end
    end)
    |> Repo.exists?()
  end

  defp unwrap(attrs) do
    Map.get(attrs, "user") || Map.get(attrs, :user) || attrs
  end
end
