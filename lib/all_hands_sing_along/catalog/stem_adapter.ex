# lib/all_hands_sing_along/catalog/stem_adapter.ex
defmodule AllHandsSingAlong.Catalog.StemAdapter do
  @moduledoc false

  @doc "Separate a file on local disk. Returns the path of the produced instrumental."
  @callback isolate(String.t(), (integer() -> any()) | nil) ::
              {:ok, String.t()} | {:error, term()}

  @doc """
  Separate audio the adapter can fetch itself from a public URL, so the app
  never has to download the original to local disk first. Cloud adapters
  implement this; local Demucs does not.
  """
  @callback isolate_url(String.t(), (integer() -> any()) | nil) ::
              {:ok, String.t()} | {:error, term()}

  @callback available?() :: boolean()

  @optional_callbacks isolate_url: 2

  @doc "True when the adapter can take a URL instead of a local file."
  @spec remote_capable?(module()) :: boolean()
  def remote_capable?(adapter) when is_atom(adapter) do
    Code.ensure_loaded?(adapter) and function_exported?(adapter, :isolate_url, 2)
  end
end
