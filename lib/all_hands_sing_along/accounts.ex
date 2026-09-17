# lib/all_hands_sing_along/accounts.ex
defmodule AllHandsSingAlong.Accounts do
  @moduledoc """
  Users who sign in with Google.
  """

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
end
