# lib/all_hands_sing_along/accounts/user.ex
defmodule AllHandsSingAlong.Accounts.User do
  @moduledoc """
  Someone who signed in with Google. `google_sub` is the stable identifier;
  email and name are refreshed on every sign-in. `username` is what rooms show.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @username_format ~r/^[A-Za-z0-9_]{2,30}$/

  schema "users" do
    field :google_sub, :string
    field :email, :string
    field :name, :string
    field :username, :string
    field :avatar_url, :string
    field :hosted_domain, :string
    field :last_signed_in_at, :utc_datetime

    has_many :hosted_rooms, AllHandsSingAlong.Rooms.Room, foreign_key: :host_user_id

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:google_sub, :email, :name, :avatar_url, :hosted_domain, :last_signed_in_at])
    |> update_change(:email, &String.downcase/1)
    |> validate_required([:google_sub, :email, :name])
    |> validate_length(:name, min: 1, max: 120)
    |> validate_format(:email, ~r/@/)
    |> unique_constraint(:google_sub)
  end

  @spec username_changeset(t(), map()) :: Ecto.Changeset.t()
  def username_changeset(user, attrs) do
    user
    |> cast(attrs, [:username])
    |> update_change(:username, &blank_to_nil/1)
    |> validate_required([:username])
    |> validate_length(:username, min: 2, max: 30)
    |> validate_format(:username, @username_format)
    |> unique_constraint(:username, name: :users_username_lower_index)
  end

  @spec username?(t() | nil) :: boolean()
  def username?(%__MODULE__{username: username}) when is_binary(username) and username != "",
    do: true

  def username?(_), do: false

  @doc "Name shown in rooms. Nil until they pick a username."
  @spec display_name(t() | nil) :: String.t() | nil
  def display_name(%__MODULE__{username: username}) when is_binary(username) and username != "",
    do: username

  def display_name(_), do: nil

  @doc "Short display name: username if set, else first name, else email local part."
  @spec short_name(t()) :: String.t()
  def short_name(%__MODULE__{username: username}) when is_binary(username) and username != "",
    do: username

  def short_name(%__MODULE__{name: name}) when is_binary(name) and name != "" do
    name |> String.split(" ", trim: true) |> List.first()
  end

  def short_name(%__MODULE__{email: email}) when is_binary(email) do
    email |> String.split("@") |> List.first()
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
