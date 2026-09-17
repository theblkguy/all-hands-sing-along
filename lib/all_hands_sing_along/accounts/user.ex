# lib/all_hands_sing_along/accounts/user.ex
defmodule AllHandsSingAlong.Accounts.User do
  @moduledoc """
  Someone who signed in with Google. `google_sub` is the stable identifier;
  email and name are refreshed on every sign-in.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "users" do
    field :google_sub, :string
    field :email, :string
    field :name, :string
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

  @doc "Short display name: first name if we have one, else the email local part."
  @spec short_name(t()) :: String.t()
  def short_name(%__MODULE__{name: name}) when is_binary(name) and name != "" do
    name |> String.split(" ", trim: true) |> List.first()
  end

  def short_name(%__MODULE__{email: email}) when is_binary(email) do
    email |> String.split("@") |> List.first()
  end
end
