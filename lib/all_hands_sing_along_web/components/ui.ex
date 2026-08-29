defmodule AllHandsSingAlongWeb.UI do
  @moduledoc false
  use Phoenix.Component

  @copy_button_class "inline-flex items-center gap-1.5 rounded-full border border-white/15 bg-white/10 px-3 py-1.5 text-xs font-medium uppercase tracking-wider text-white/80 transition hover:border-amber-200/40 hover:bg-white/15 hover:text-amber-100"

  def copy_button_class, do: @copy_button_class

  attr :n, :any, required: true
  attr :class, :any, default: "size-6 text-xs"

  def step_item(assigns) do
    ~H"""
    <span class={[
      "flex shrink-0 items-center justify-center rounded-full border border-amber-200/30 bg-amber-200/10 font-medium text-amber-100",
      @class
    ]}>
      {@n}
    </span>
    """
  end
end
