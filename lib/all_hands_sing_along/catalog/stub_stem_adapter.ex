# lib/all_hands_sing_along/catalog/stub_stem_adapter.ex
defmodule AllHandsSingAlong.Catalog.StubStemAdapter do
  @moduledoc false

  @behaviour AllHandsSingAlong.Catalog.StemAdapter

  def isolate(input_path) when is_binary(input_path), do: isolate(input_path, nil)

  @impl true
  def isolate(input_path, progress) when is_binary(input_path) do
    if is_function(progress, 1) do
      progress.(50)
      progress.(100)
    end

    case Application.get_env(:all_hands_sing_along, :stem_stub, :ok) do
      :ok -> {:ok, input_path}
      {:error, reason} -> {:error, reason}
    end
  end
end
