# lib/all_hands_sing_along/catalog/stem_adapter.ex
defmodule AllHandsSingAlong.Catalog.StemAdapter do
  @moduledoc false

  @callback isolate(String.t(), (integer() -> any()) | nil) ::
              {:ok, String.t()} | {:error, term()}

  @callback available?() :: boolean()
end
