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
          <p class="text-xs font-medium uppercase tracking-[0.28em] text-amber-100/70">
            {if @host?, do: "Host guide", else: "Guest guide"}
          </p>
          <h2 id="onboarding-title" class="mt-2 text-2xl font-semibold tracking-tight text-white">
            {if @host?, do: "You're hosting", else: "You're in the room"}
          </h2>
          <p class="mt-2 text-sm leading-relaxed text-white/65">
            {if @host?,
              do: "You run the queue and the clock. Guests add songs and sing along.",
              else: "The host runs playback. You add songs, watch lyrics, and wait your turn."}
          </p>

          <ol :if={@host?} class="mt-6 space-y-4">
            <li class="flex gap-3 text-sm leading-relaxed text-white/75">
              <.step_item n={1} class="mt-0.5 size-6 text-xs" />
              <span>
                Share room code <span class="font-mono tracking-wider text-white">{@room_code}</span>
                and the site URL. Keep this browser tab open — clearing cookies drops host controls.
              </span>
            </li>
            <li class="flex gap-3 text-sm leading-relaxed text-white/75">
              <.step_item n={2} class="mt-0.5 size-6 text-xs" />
              <span>Headphones on. Zoom is for faces only.</span>
            </li>
            <li class="flex gap-3 text-sm leading-relaxed text-white/75">
              <.step_item n={3} class="mt-0.5 size-6 text-xs" />
              <span>
                Wait until a song is <span class="text-white">Ready</span>
                (instrumental + lyrics), then hit Start singer.
              </span>
            </li>
            <li class="flex gap-3 text-sm leading-relaxed text-white/75">
              <.step_item n={4} class="mt-0.5 size-6 text-xs" />
              <span>
                Play, Pause, and Skip control everyone. Use Lyrics later / earlier if the line is off.
              </span>
            </li>
            <li class="flex gap-3 text-sm leading-relaxed text-white/75">
              <.step_item n={5} class="mt-0.5 size-6 text-xs" />
              <span>
                If a song is stuck on Preparing: upload audio, search or paste lyrics, or Use original anyway.
              </span>
            </li>
          </ol>

          <p
            :if={@host? and not @stem_local?}
            id="onboarding-worker-note"
            class="mt-4 text-sm leading-relaxed text-amber-100/80"
          >
            Vocal isolation runs on your Mac. Use the command at the top of this page.
          </p>

          <ol :if={not @host?} class="mt-6 space-y-4">
            <li class="flex gap-3 text-sm leading-relaxed text-white/75">
              <.step_item n={1} class="mt-0.5 size-6 text-xs" />
              <span>Headphones on. Stay on Zoom for faces.</span>
            </li>
            <li class="flex gap-3 text-sm leading-relaxed text-white/75">
              <.step_item n={2} class="mt-0.5 size-6 text-xs" />
              <span>
                Add yourself to the queue with a title and artist. Audio is optional; lyrics usually fetch on their own.
              </span>
            </li>
            <li class="flex gap-3 text-sm leading-relaxed text-white/75">
              <.step_item n={3} class="mt-0.5 size-6 text-xs" />
              <span>
                Wait until the song is <span class="text-white">Ready</span>. The host starts playback for everyone.
              </span>
            </li>
            <li class="flex gap-3 text-sm leading-relaxed text-white/75">
              <.step_item n={4} class="mt-0.5 size-6 text-xs" />
              <span>Don't scrub the audio bar. It does not drive the room clock.</span>
            </li>
            <li class="flex gap-3 text-sm leading-relaxed text-white/75">
              <.step_item n={5} class="mt-0.5 size-6 text-xs" />
              <span>
                <span class="text-white">In the room</span> is who is online, not singer order.
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
