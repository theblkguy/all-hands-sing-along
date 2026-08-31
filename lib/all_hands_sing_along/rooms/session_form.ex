# lib/all_hands_sing_along/rooms/session_form.ex
defmodule AllHandsSingAlong.Rooms.SessionForm do
  @moduledoc """
  Host/join params. Blank strings become nil so validate_required can fail.
  """
  use Ecto.Schema
  import Ecto.Changeset

  embedded_schema do
    field :display_name, :string
    field :code, :string
  end

  @spec host_changeset(map()) :: Ecto.Changeset.t()
  def host_changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(unwrap(attrs, "host"), [:display_name])
    |> update_change(:display_name, &blank_to_nil/1)
    |> validate_required([:display_name])
    |> validate_length(:display_name, min: 1, max: 80)
  end

  @spec join_changeset(map()) :: Ecto.Changeset.t()
  def join_changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(unwrap(attrs, "join"), [:display_name, :code])
    |> update_change(:display_name, &blank_to_nil/1)
    |> update_change(:code, &blank_to_nil/1)
    |> validate_required([:display_name, :code])
    |> validate_length(:display_name, min: 1, max: 80)
    |> validate_length(:code, min: 4, max: 8)
  end

  defp unwrap(attrs, "host"), do: Map.get(attrs, "host") || Map.get(attrs, :host) || attrs
  defp unwrap(attrs, "join"), do: Map.get(attrs, "join") || Map.get(attrs, :join) || attrs

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
