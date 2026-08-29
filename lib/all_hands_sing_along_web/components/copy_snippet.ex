# lib/all_hands_sing_along_web/components/copy_snippet.ex
defmodule AllHandsSingAlongWeb.CopySnippet do
  @moduledoc false
  use Phoenix.Component

  import AllHandsSingAlongWeb.CoreComponents, only: [icon: 1]
  import AllHandsSingAlongWeb.UI, only: [copy_button_class: 0]

  attr :id, :string, required: true
  attr :text, :string, required: true
  attr :pre_id, :string, default: nil
  attr :label, :string, default: "Copy"

  def copy_snippet(assigns) do
    assigns = assign(assigns, :command_id, assigns.pre_id || "#{assigns.id}-text")

    ~H"""
    <div id={"#{@id}-root"} class="mt-2" phx-hook="ClipboardCopy">
      <div class="flex items-center justify-end">
        <button
          id={@id}
          type="button"
          data-copy-button
          class={copy_button_class()}
        >
          <.icon name="hero-clipboard-document" class="size-4" />
          <span data-copy-label>{@label}</span>
        </button>
      </div>
      <pre
        id={@command_id}
        class="mt-2 overflow-x-auto rounded-lg bg-black/35 px-3 py-2 font-mono text-[13px] leading-relaxed text-amber-50"
      >{@text}</pre>
    </div>
    """
  end
end
