defmodule AllHandsSingAlongWeb.Onboarding do
  @moduledoc """
  First-visit room overlay and copy-code control.
  """
  use AllHandsSingAlongWeb, :html

  attr :host?, :boolean, required: true
  attr :stem_local?, :boolean, default: true
  attr :show?, :boolean, required: true
  attr :room_code, :string, required: true

  def gate(assigns) do
    ~H"""
    <div
      id="onboarding-gate"
      phx-hook=".OnboardingGate"
      data-role={if(@host?, do: "host", else: "guest")}
    >
      <div
        :if={@show?}
        class="fixed inset-0 z-50 flex items-center justify-center p-4 sm:p-6"
      >
        <div class="absolute inset-0 bg-black/65 backdrop-blur-sm" aria-hidden="true"></div>
        <div
          id="onboarding-overlay"
          role="dialog"
          aria-modal="true"
          aria-labelledby="onboarding-title"
          class="glass-panel relative max-h-[min(36rem,calc(100dvh-2rem))] w-full max-w-lg overflow-y-auto rounded-3xl p-6 sm:p-8"
        >
          <h2 id="onboarding-title" class="text-2xl font-semibold tracking-tight text-white">
            {if @host?, do: "You're hosting", else: "You're in the room"}
          </h2>
          <p class="mt-2 text-sm leading-relaxed text-white/65">
            {if @host?,
              do: "You start and stop the songs. Everyone else adds themselves and sings.",
              else: "The host plays the songs. Add yours, follow the lyrics, and wait your turn."}
          </p>

          <ol :if={@host?} class="mt-6 space-y-4">
            <li class="flex gap-3 text-sm leading-relaxed text-white/75">
              <.step_item n={1} class="mt-0.5 size-6 text-xs" />
              <span>
                Send people code <span class="font-mono tracking-wider text-white">{@room_code}</span>
                and this URL. Keep this tab open — clearing cookies drops host controls.
              </span>
            </li>
            <li class="flex gap-3 text-sm leading-relaxed text-white/75">
              <.step_item n={2} class="mt-0.5 size-6 text-xs" />
              <span>Wear headphones so Zoom doesn't pick up the track.</span>
            </li>
            <li class="flex gap-3 text-sm leading-relaxed text-white/75">
              <.step_item n={3} class="mt-0.5 size-6 text-xs" />
              <span>
                When a song is <span class="text-white">Ready</span>
                (track + lyrics), hit Start singer.
              </span>
            </li>
            <li class="flex gap-3 text-sm leading-relaxed text-white/75">
              <.step_item n={4} class="mt-0.5 size-6 text-xs" />
              <span>
                Play, Pause, and Skip move everyone. Later / Earlier if the lyrics are off.
              </span>
            </li>
            <li class="flex gap-3 text-sm leading-relaxed text-white/75">
              <.step_item n={5} class="mt-0.5 size-6 text-xs" />
              <span>
                Stuck on Preparing? Add audio, search or paste lyrics, or Play original.
              </span>
            </li>
          </ol>

          <p
            :if={@host? and not @stem_local?}
            id="onboarding-worker-note"
            class="mt-4 text-sm leading-relaxed text-amber-100/80"
          >
            To strip vocals, click Show Mac command at the top of this page and run it in Terminal
            (after the README setup).
          </p>

          <ol :if={not @host?} class="mt-6 space-y-4">
            <li class="flex gap-3 text-sm leading-relaxed text-white/75">
              <.step_item n={1} class="mt-0.5 size-6 text-xs" />
              <span>Wear headphones, and stay on Zoom for faces.</span>
            </li>
            <li class="flex gap-3 text-sm leading-relaxed text-white/75">
              <.step_item n={2} class="mt-0.5 size-6 text-xs" />
              <span>
                Add a title and artist. Audio is optional; lyrics usually show up on their own.
              </span>
            </li>
            <li class="flex gap-3 text-sm leading-relaxed text-white/75">
              <.step_item n={3} class="mt-0.5 size-6 text-xs" />
              <span>
                Wait until the song is <span class="text-white">Ready</span>. The host starts everyone together.
              </span>
            </li>
            <li class="flex gap-3 text-sm leading-relaxed text-white/75">
              <.step_item n={4} class="mt-0.5 size-6 text-xs" />
              <span>Don't drag the audio bar — it won't change the room.</span>
            </li>
            <li class="flex gap-3 text-sm leading-relaxed text-white/75">
              <.step_item n={5} class="mt-0.5 size-6 text-xs" />
              <span>
                <span class="text-white">In the room</span> is who's here, not the singing order.
              </span>
            </li>
          </ol>

          <div class="mt-8">
            <.button
              id="dismiss-onboarding"
              type="button"
              variant="primary"
              phx-click="dismiss_onboarding"
            >
              Got it
            </.button>
          </div>
        </div>
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".OnboardingGate">
        const storageKey = (role) => `ahss:onboarding:${role || "guest"}`

        export default {
          mounted() {
            this.role = this.el.dataset.role || "guest"
            this.wasOpen = !!this.el.querySelector("#onboarding-overlay")

            if (!localStorage.getItem(storageKey(this.role))) {
              this.pushEvent("open_onboarding", {})
            }

            this.el.addEventListener("click", (event) => {
              if (event.target.closest("#dismiss-onboarding")) {
                localStorage.setItem(storageKey(this.role), "1")
              }
            })

            this.onKeyDown = (event) => {
              if (event.key !== "Escape") return
              if (!this.el.querySelector("#onboarding-overlay")) return
              event.preventDefault()
              localStorage.setItem(storageKey(this.role), "1")
              this.pushEvent("dismiss_onboarding", {})
            }

            document.addEventListener("keydown", this.onKeyDown)
            this.focusDismiss()
          },
          updated() {
            const open = !!this.el.querySelector("#onboarding-overlay")
            if (open && !this.wasOpen) this.focusDismiss()
            this.wasOpen = open
          },
          destroyed() {
            document.removeEventListener("keydown", this.onKeyDown)
          },
          focusDismiss() {
            this.el.querySelector("#dismiss-onboarding")?.focus()
          }
        }
      </script>
    </div>
    """
  end

  attr :code, :string, required: true

  def copy_code(assigns) do
    ~H"""
    <button
      id="copy-room-code"
      type="button"
      phx-hook="ClipboardCopy"
      phx-update="ignore"
      data-copy-button
      data-copy-text={@code}
      class={copy_button_class()}
    >
      <.icon name="hero-clipboard-document" class="size-4" />
      <span id="copy-room-code-label" data-copy-label>Copy code</span>
    </button>
    """
  end
end
