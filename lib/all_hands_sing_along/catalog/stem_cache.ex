# lib/all_hands_sing_along/catalog/stem_cache.ex
defmodule AllHandsSingAlong.Catalog.StemCache do
  @moduledoc """
  Finished instrumentals keyed by the SHA-256 of the uploaded original.

  All-hands sing-alongs converge on the same songs. Once anyone in any room has
  had a track separated, every later upload of the same bytes is instant and
  costs nothing. Rows are never deleted; the referenced object in Tigris is
  shared by every song that hits the cache, so nothing should remove it.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias AllHandsSingAlong.Repo

  @type t :: %__MODULE__{}

  schema "stem_cache" do
    field :content_hash, :string
    field :vocal_mix, :float, default: 0.12
    field :instrumental_path, :string
    field :hits, :integer, default: 0
    field :source, :string

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(cache, attrs) do
    cache
    |> cast(attrs, [:content_hash, :vocal_mix, :instrumental_path, :hits, :source])
    |> validate_required([:content_hash, :vocal_mix, :instrumental_path])
    |> validate_length(:content_hash, is: 64)
    |> unique_constraint([:content_hash, :vocal_mix])
  end

  @doc """
  Returns the cached instrumental path for this original, or nil.
  Bumps the hit counter as a side effect so you can see what people sing.
  """
  @spec lookup(String.t() | nil, number()) :: String.t() | nil
  def lookup(content_hash, vocal_mix) when is_binary(content_hash) and is_number(vocal_mix) do
    mix = normalize_mix(vocal_mix)

    case Repo.get_by(__MODULE__, content_hash: content_hash, vocal_mix: mix) do
      nil ->
        nil

      %__MODULE__{id: id, instrumental_path: path} ->
        from(c in __MODULE__, where: c.id == ^id)
        |> Repo.update_all(inc: [hits: 1])

        path
    end
  end

  def lookup(_, _), do: nil

  @doc """
  Records a finished instrumental. Safe to call twice; the first write wins.
  """
  @spec put(String.t() | nil, number(), String.t(), String.t() | nil) :: :ok
  def put(content_hash, vocal_mix, instrumental_path, source \\ nil)

  def put(content_hash, vocal_mix, instrumental_path, source)
      when is_binary(content_hash) and is_number(vocal_mix) and is_binary(instrumental_path) do
    attrs = %{
      content_hash: content_hash,
      vocal_mix: normalize_mix(vocal_mix),
      instrumental_path: instrumental_path,
      source: source
    }

    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:content_hash, :vocal_mix])

    :ok
  end

  def put(_, _, _, _), do: :ok

  @spec count() :: non_neg_integer()
  def count, do: Repo.aggregate(__MODULE__, :count)

  # Floats as SQLite keys are fine as long as they're written identically each
  # time; round to two places so 0.12 and 0.120000001 collide.
  defp normalize_mix(mix), do: Float.round(mix / 1, 2)
end
