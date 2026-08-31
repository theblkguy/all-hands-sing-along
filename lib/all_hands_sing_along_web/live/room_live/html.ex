defmodule AllHandsSingAlongWeb.RoomLive.HTML do
  @moduledoc false
  use AllHandsSingAlongWeb, :html

  import AllHandsSingAlongWeb.Onboarding, only: [copy_code: 1]

  alias AllHandsSingAlong.Catalog

  def can_attach_audio?(host?, display_name, entry) do
    host? or entry.singer_name == display_name
  end

  def can_preview_lyrics?(entry) do
    entry.status in [:requested, :preparing, :ready] and
      Catalog.has_original?(entry.song) and
      Catalog.has_lyrics?(entry.song)
  end

  def can_replace_lyrics?(entry) do
    entry.status in [:requested, :preparing, :ready] and Catalog.has_lyrics?(entry.song)
  end

  def can_attach_missing_lyrics?(entry) do
    entry.status in [:requested, :preparing] and not Catalog.has_lyrics?(entry.song)
  end

  def room(assigns) do
    ~H"""
    <div class="space-y-8">
      <.headphones_banner />
      <.stem_worker_hint
        :if={@host? and not @stem_local?}
        room_code={@room.code}
        host_token={@host_token}
        show_command?={@show_worker_command?}
      />
      <.room_header room={@room} host?={@host?} display_name={@display_name} />
      <.now_playing host?={@host?} playback={@playback} lyric_preview={@lyric_preview} />
      <.lyric_preview_card :if={@host? and @lyric_preview} lyric_preview={@lyric_preview} />
      <.queue_and_presence {assigns} />
    </div>
    """
  end

  defp headphones_banner(assigns) do
    ~H"""
    <div
      class="glass-panel flex items-center gap-3 rounded-full px-4 py-2 text-sm text-amber-100/80"
      title="Use headphones so the backing track does not leak into Zoom."
    >
      <.icon name="hero-speaker-x-mark" class="size-5 shrink-0 text-amber-200" />
      <span class="sr-only">
        Use headphones so the backing track does not leak into Zoom.
      </span>
      <span class="hidden sm:inline">Headphones on. Keep the mix out of Zoom.</span>
    </div>
    """
  end

  attr :room_code, :string, required: true
  attr :host_token, :string, default: nil
  attr :show_command?, :boolean, default: false

  defp stem_worker_hint(assigns) do
    ~H"""
    <div id="stem-worker-hint" class="glass-panel rounded-2xl px-4 py-3 text-sm text-amber-100/85">
      <p class="font-medium text-amber-100">Vocal isolation runs on your Mac</p>
      <p class="mt-1 text-white/70">
        Run this after <span class="font-medium text-white">./script/setup</span>, from the
        project folder. It only processes <span class="font-medium text-white">this room</span>.
        Other hosts run their own copy. Guests do not need it.
      </p>
      <.button
        :if={not @show_command?}
        id="reveal-worker-command"
        type="button"
        phx-click="reveal_worker_command"
        class="btn btn-sm mt-3"
      >
        Show Mac worker command
      </.button>
      <.copy_snippet
        :if={@show_command? and is_binary(@host_token)}
        id="copy-stem-worker"
        pre_id="stem-worker-command"
        text={"./script/worker --room #{@room_code} --token #{@host_token}"}
      />
    </div>
    """
  end

  attr :room, :map, required: true
  attr :host?, :boolean, required: true
  attr :display_name, :string, required: true

  defp room_header(assigns) do
    ~H"""
    <div class="flex flex-wrap items-end justify-between gap-4">
      <div>
        <p class="text-xs font-medium uppercase tracking-[0.28em] text-white/45">Room code</p>
        <div class="mt-1 flex flex-wrap items-center gap-3">
          <h1 class="font-mono text-4xl font-semibold tracking-[0.2em] text-white">
            {@room.code}
          </h1>
          <.copy_code code={@room.code} />
        </div>
        <div class="mt-2 flex flex-wrap items-center gap-2">
          <p class="text-sm text-white/65">
            You are {@display_name}
            <.host_badge :if={@host?} class="ml-2 bg-amber-200/15 text-[11px]" />
          </p>
          <button
            id="open-onboarding"
            type="button"
            phx-click="open_onboarding"
            class="inline-flex items-center gap-1.5 rounded-full border border-white/15 bg-white/10 px-3 py-1 text-xs font-medium uppercase tracking-wider text-white/80 transition hover:border-amber-200/40 hover:bg-white/15 hover:text-amber-100"
          >
            <.icon name="hero-question-mark-circle" class="size-4" /> Help
          </button>
        </div>
      </div>
      <div :if={@host?} class="flex flex-col items-end gap-2">
        <div class="flex flex-wrap items-center justify-end gap-2">
          <.icon_button
            id="start-singer"
            icon="hero-play"
            label="Start singer"
            variant="primary"
            phx-click="play"
          />
          <.icon_button id="pause-song" icon="hero-pause" label="Pause" phx-click="pause" />
          <.icon_button id="skip-song" icon="hero-forward" label="Skip" phx-click="skip" />
        </div>
        <p class="text-xs text-white/45">Backing track, no vocals</p>
      </div>
    </div>
    """
  end

  attr :host?, :boolean, required: true
  attr :playback, :any, required: true
  attr :lyric_preview, :any, required: true

  defp now_playing(assigns) do
    ~H"""
    <div class="glass-panel space-y-5 rounded-3xl p-6 sm:p-8">
      <div class="flex flex-wrap items-start justify-between gap-3">
        <p class="text-xs font-medium uppercase tracking-[0.28em] text-white/45">Now playing</p>
        <p
          :if={playback_mode(@playback)}
          id="playback-mode"
          class="rounded-full border border-white/15 px-3 py-1 text-xs text-white/70"
        >
          {playback_mode_label(@playback)}
        </p>
      </div>
      <p id="now-playing-title" class="text-2xl font-medium tracking-tight text-white sm:text-3xl">
        {playback_heading(@playback)}
      </p>
      <p
        :if={not @host? and playback_empty?(@playback)}
        id="guest-playback-hint"
        class="text-sm text-white/55"
      >
        The host starts the singer when a song is Ready.
      </p>
      <p :if={@playback && @playback.singer_name} id="now-playing-singer" class="text-white/60">
        {@playback.singer_name}
      </p>
      <.lyric_stage
        id="karaoke-player"
        hook="KaraokePlayer"
        outgoing_id="lyric-line-outgoing"
        line_id="lyric-line"
        audio_id="karaoke-audio"
        audio_url={@playback && @playback.audio_url}
        playing={@playback && @playback.playing?}
      />
      <.lyric_nudge_controls
        :if={@host?}
        later_id="lyrics-later"
        earlier_id="lyrics-earlier"
        offset_id="lyrics-offset"
        event="nudge_lyrics"
        offset_ms={@playback && @playback.offset_ms}
      />
      <p
        :if={@host? and @lyric_preview}
        id="singer-muted-note"
        class="text-sm text-amber-100/70"
      >
        Singer track is muted in your headphones while you tune the next song.
      </p>
    </div>
    """
  end

  attr :lyric_preview, :map, required: true

  defp lyric_preview_card(assigns) do
    ~H"""
    <div id="lyric-preview-card" class="glass-panel space-y-4 rounded-3xl p-6">
      <div class="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p class="text-xs font-medium uppercase tracking-[0.28em] text-white/45">
            Tune next song
          </p>
          <p id="lyric-preview-title" class="mt-1 text-xl font-medium text-white">
            {Catalog.format_title(@lyric_preview.title, @lyric_preview.artist)}
          </p>
          <p class="text-white/60">{@lyric_preview.singer_name}</p>
        </div>
        <.icon_button
          id="close-lyric-preview"
          icon="hero-x-mark"
          label="Close preview"
          phx-click="close_lyric_preview"
        />
      </div>
      <p class="text-sm text-white/55">Original mix (vocals on). Guests still hear the singer.</p>
      <.lyric_stage
        id="lyric-preview"
        hook="LyricPreview"
        outgoing_id="lyric-preview-line-outgoing"
        line_id="lyric-preview-line"
        audio_id="lyric-preview-audio"
      />
      <.lyric_nudge_controls
        later_id="preview-lyrics-later"
        earlier_id="preview-lyrics-earlier"
        offset_id="lyric-preview-offset"
        event="nudge_preview"
        offset_ms={@lyric_preview.offset_ms}
      />
    </div>
    """
  end

  defp queue_and_presence(assigns) do
    ~H"""
    <div class="grid gap-6 lg:grid-cols-3">
      <.queue_section {assigns} />
      <section class="glass-panel space-y-3 rounded-3xl p-5">
        <h2 class="text-lg font-medium text-white">In the room</h2>
        <ul class="space-y-2">
          <li :for={person <- @presence} class="flex items-center gap-2 text-white/80">
            <span>{person.name}</span>
            <.host_badge :if={person.host?} class="text-[10px]" />
          </li>
        </ul>
      </section>
    </div>
    """
  end

  defp queue_section(assigns) do
    ~H"""
    <section class="lg:col-span-2 space-y-4">
      <h2 class="text-lg font-medium text-white">Queue</h2>

      <.form
        for={@song_form}
        id="add-queue-form"
        phx-change="validate_queue"
        phx-submit="add_to_queue"
        class="glass-panel space-y-4 rounded-3xl p-6"
      >
        <h3 class="font-medium text-white">Add a song</h3>
        <p id="add-song-hint" class="text-sm leading-relaxed text-white/55">
          Lyrics are fetched automatically. You can upload audio now or after you join the queue.
        </p>
        <.input field={@song_form[:title]} id="song-title" label="Song title" />
        <.input field={@song_form[:artist]} id="song-artist" label="Artist" />
        <div>
          <p class="label mb-1">Audio (optional)</p>
          <p id="audio-types-hint" class="mb-1 text-xs text-white/45">
            mp3, wav, m4a, or ogg. Max 32 MB.
          </p>
          <.live_file_input upload={@uploads.audio} class="file-input file-input-bordered w-full" />
          <.error :for={err <- all_upload_errors(@uploads.audio)}>{upload_error_text(err)}</.error>
          <.upload_progress id="audio-upload-progress" entries={@uploads.audio.entries} />
        </div>
        <div>
          <p class="label mb-1">Lyrics .lrc (optional)</p>
          <p id="lrc-types-hint" class="mb-1 text-xs text-white/45">.lrc, max 200 KB.</p>
          <.live_file_input upload={@uploads.lrc} class="file-input file-input-bordered w-full" />
          <.error :for={err <- all_upload_errors(@uploads.lrc)}>{upload_error_text(err)}</.error>
          <.upload_progress id="lrc-upload-progress" entries={@uploads.lrc.entries} />
        </div>
        <.button type="submit" variant="primary">Add me to the queue</.button>
      </.form>

      <ul id="queue" phx-update="stream" class="space-y-2">
        <li
          id="queue-empty"
          class="hidden only:block glass-panel rounded-2xl px-5 py-8 text-center text-sm text-white/55"
        >
          No singers yet. Add a song below.
        </li>
        <.queue_item
          :for={{dom_id, entry} <- @streams.queue}
          id={dom_id}
          entry={entry}
          host?={@host?}
          display_name={@display_name}
          lyric_search={@lyric_search}
          changing_lyrics_id={@changing_lyrics_id}
          attaching_audio_id={@attaching_audio_id}
          late_audio={@uploads.late_audio}
        />
      </ul>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :entry, :map, required: true
  attr :host?, :boolean, required: true
  attr :display_name, :string, required: true
  attr :lyric_search, :any, default: nil
  attr :changing_lyrics_id, :any, default: nil
  attr :attaching_audio_id, :any, default: nil
  attr :late_audio, :map, required: true

  defp queue_item(assigns) do
    ~H"""
    <li id={@id} class="glass-panel rounded-2xl px-5 py-4">
      <div class="flex flex-col gap-3">
        <div class="flex flex-wrap items-center justify-between gap-2">
          <div>
            <p class="font-medium text-white">
              {Catalog.format_title(@entry.song_title, @entry.song && @entry.song.artist)}
            </p>
            <p class="text-sm text-white/55">{@entry.singer_name}</p>
            <p
              :if={@entry.status in [:requested, :preparing] and Catalog.missing_audio?(@entry.song)}
              id={"no-audio-#{@entry.id}"}
              class="text-sm text-warning"
            >
              No song file yet. Upload one if you joined the queue first.
            </p>
            <p
              :if={@entry.status == :preparing and not Catalog.has_lyrics?(@entry.song)}
              id={"no-lyrics-#{@entry.id}"}
              class="text-sm text-warning"
            >
              Couldn't find timed lyrics. Search with a fuller title, or paste an .lrc.
            </p>
            <p
              :if={Catalog.stem_in_progress?(@entry.song)}
              id={"stem-progress-#{@entry.id}"}
              class="space-y-1"
            >
              <span class="text-sm text-base-content/70">
                {stem_progress_label(@entry.song)}
              </span>
              <progress
                class="progress w-full"
                max="100"
                value={@entry.song.stem_progress || 0}
              ></progress>
            </p>
            <p
              :if={Catalog.stem_failed?(@entry.song)}
              id={"stem-failed-#{@entry.id}"}
              class="text-sm text-warning"
            >
              {@entry.song.stem_error || "Couldn't remove vocals."}
            </p>
          </div>
          <span class="rounded-full border border-white/15 px-2.5 py-0.5 text-[11px] uppercase tracking-wider text-white/60">
            {status_label(@entry.status)}
          </span>
        </div>
        <div
          :if={can_attach_missing_lyrics?(@entry)}
          class="space-y-3 border-t border-white/10 pt-3"
        >
          <.lyrics_editor entry={@entry} lyric_search={@lyric_search} />
        </div>
        <div
          :if={@host? and can_replace_lyrics?(@entry)}
          class="space-y-3 border-t border-white/10 pt-3"
        >
          <.icon_button
            id={"change-lyrics-#{@entry.id}"}
            icon="hero-magnifying-glass"
            label={
              if @changing_lyrics_id == @entry.id, do: "Hide lyrics search", else: "Change lyrics"
            }
            class={icon_button_class(if(@changing_lyrics_id == @entry.id, do: "primary", else: nil))}
            phx-click="toggle_change_lyrics"
            phx-value-id={@entry.id}
          />
          <div :if={@changing_lyrics_id == @entry.id} class="space-y-3">
            <.lyrics_editor entry={@entry} lyric_search={@lyric_search} />
          </div>
        </div>
        <div
          :if={
            can_attach_audio?(@host?, @display_name, @entry) and
              Catalog.missing_audio?(@entry.song) and
              @entry.status in [:requested, :preparing]
          }
          class="space-y-2 border-t border-white/10 pt-3"
        >
          <.icon_button
            :if={@attaching_audio_id != @entry.id}
            id={"start-attach-audio-#{@entry.id}"}
            icon="hero-arrow-up-tray"
            label="Upload audio"
            phx-click="start_attach_audio"
            phx-value-id={@entry.id}
          />
          <.form
            :if={@attaching_audio_id == @entry.id}
            for={%{}}
            id={"attach-audio-#{@entry.id}"}
            phx-change="validate_late_audio"
            phx-submit="attach_audio"
            class="space-y-2"
          >
            <input type="hidden" name="entry_id" value={@entry.id} />
            <.live_file_input upload={@late_audio} class="file-input file-input-bordered w-full" />
            <p class="text-xs text-white/45">mp3, wav, m4a, or ogg. Max 32 MB.</p>
            <.error :for={err <- all_upload_errors(@late_audio)}>{upload_error_text(err)}</.error>
            <.upload_progress
              id={"late-audio-progress-#{@entry.id}"}
              entries={@late_audio.entries}
            />
            <.button type="submit">Save audio</.button>
          </.form>
        </div>
        <div :if={@host? and Catalog.needs_isolation?(@entry.song)} class="flex flex-wrap gap-2">
          <.icon_button
            :if={Catalog.stem_in_progress?(@entry.song)}
            id={"cancel-stems-#{@entry.id}"}
            icon="hero-stop"
            label="Cancel"
            phx-click="cancel_stems"
            phx-value-id={@entry.id}
          />
          <.icon_button
            :if={not Catalog.stem_in_progress?(@entry.song)}
            id={"retry-stems-#{@entry.id}"}
            icon="hero-arrow-path"
            label={stem_retry_label(@entry.song)}
            phx-click="retry_stems"
            phx-value-id={@entry.id}
          />
          <.icon_button
            id={"use-original-#{@entry.id}"}
            icon="hero-speaker-wave"
            label="Use original anyway"
            phx-click="use_original"
            phx-value-id={@entry.id}
          />
        </div>
        <.icon_button
          :if={@host? and can_preview_lyrics?(@entry)}
          id={"tune-lyrics-#{@entry.id}"}
          icon="hero-adjustments-horizontal"
          label="Tune lyrics"
          phx-click="tune_lyrics"
          phx-value-id={@entry.id}
        />
        <div :if={@host? and @entry.status == :ready} class="flex flex-wrap gap-2">
          <.icon_button
            id={"move-up-#{@entry.id}"}
            icon="hero-chevron-up"
            label="Move up"
            phx-click="move_ready"
            phx-value-id={@entry.id}
            phx-value-direction="up"
          />
          <.icon_button
            id={"move-down-#{@entry.id}"}
            icon="hero-chevron-down"
            label="Move down"
            phx-click="move_ready"
            phx-value-id={@entry.id}
            phx-value-direction="down"
          />
        </div>
      </div>
    </li>
    """
  end

  attr :id, :string, required: true
  attr :entries, :list, required: true

  defp upload_progress(assigns) do
    ~H"""
    <div :for={entry <- @entries} id={@id} class="space-y-1 pt-2">
      <p class="text-sm text-base-content/70">Uploading {entry.progress}%</p>
      <progress class="progress w-full" max="100" value={entry.progress}></progress>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :hook, :string, required: true
  attr :outgoing_id, :string, required: true
  attr :line_id, :string, required: true
  attr :audio_id, :string, required: true
  attr :audio_url, :string, default: nil
  attr :playing, :any, default: nil

  defp lyric_stage(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook={@hook}
      phx-update="ignore"
      data-playing={@playing}
      class="space-y-4"
    >
      <div class="lyric-roll">
        <p id={@outgoing_id} class="lyric-roll-line is-outgoing" aria-hidden="true"></p>
        <p id={@line_id} class="lyric-roll-line is-current"></p>
      </div>
      <audio id={@audio_id} controls class="w-full" preload="auto">
        <source :if={@audio_url} src={@audio_url} />
      </audio>
    </div>
    """
  end

  attr :later_id, :string, required: true
  attr :earlier_id, :string, required: true
  attr :offset_id, :string, required: true
  attr :event, :string, required: true
  attr :offset_ms, :any, default: nil

  defp lyric_nudge_controls(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-2">
      <.icon_button
        id={@later_id}
        icon="hero-minus"
        label="Lyrics later"
        visible_label="Later"
        phx-click={@event}
        phx-value-delta="-100"
      />
      <.icon_button
        id={@earlier_id}
        icon="hero-plus"
        label="Lyrics earlier"
        visible_label="Earlier"
        phx-click={@event}
        phx-value-delta="100"
      />
      <p id={@offset_id} class="text-sm text-white/55">
        {offset_label(@offset_ms)}
      </p>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :visible_label, :string, default: nil
  attr :variant, :string, default: nil
  attr :class, :any, default: nil

  attr :rest, :global,
    include: ~w(disabled phx-click phx-value-id phx-value-delta phx-value-direction)

  defp icon_button(assigns) do
    assigns =
      assigns
      |> assign(:computed_class, assigns.class || icon_button_class(assigns.variant))
      |> assign(:shown_label, assigns.visible_label || assigns.label)

    ~H"""
    <.button
      id={@id}
      type="button"
      class={@computed_class}
      aria-label={@label}
      title={@label}
      {@rest}
    >
      <.icon name={@icon} class="size-5 shrink-0" />
      <span>{@shown_label}</span>
    </.button>
    """
  end

  defp icon_button_class("primary") do
    "inline-flex h-10 items-center justify-center gap-2 rounded-full border border-amber-200/40 bg-amber-200 px-4 text-sm font-medium text-neutral-950 transition hover:bg-amber-100"
  end

  defp icon_button_class(_) do
    "inline-flex h-10 items-center justify-center gap-2 rounded-full border border-white/15 bg-white/10 px-3.5 text-sm font-medium text-white transition hover:border-amber-200/40 hover:bg-white/15 hover:text-amber-100"
  end

  attr :entry, :map, required: true
  attr :lyric_search, :map, default: nil

  defp lyrics_editor(assigns) do
    ~H"""
    <.form for={%{}} id={"lyrics-search-#{@entry.id}"} phx-submit="search_lyrics" class="space-y-2">
      <input type="hidden" name="entry_id" value={@entry.id} />
      <.input
        id={"lyrics-title-#{@entry.id}"}
        name="title"
        label="Title"
        value={@entry.song_title}
        required
      />
      <.input
        id={"lyrics-artist-#{@entry.id}"}
        name="artist"
        label="Artist"
        value={(@entry.song && @entry.song.artist) || ""}
        required
      />
      <.button type="submit">Search lyrics</.button>
    </.form>
    <div
      :if={@lyric_search && @lyric_search.entry_id == @entry.id}
      id={"lyrics-results-#{@entry.id}"}
      class="space-y-2"
    >
      <p :if={@lyric_search.error} class="text-sm text-warning">
        {@lyric_search.error}
      </p>
      <button
        :for={hit <- @lyric_search.results}
        id={"pick-lyrics-#{@entry.id}-#{hit.id}"}
        type="button"
        class="btn btn-sm btn-soft w-full justify-start text-left"
        phx-click="pick_lyrics"
        phx-value-id={@entry.id}
        phx-value-lrclib-id={hit.id}
      >
        {Catalog.format_title(hit.track_name, hit.artist_name)}
        <span :if={hit.album_name} class="text-base-content/60 font-normal">
          · {hit.album_name}
        </span>
      </button>
    </div>
    <.form for={%{}} id={"lyrics-paste-#{@entry.id}"} phx-submit="paste_lyrics" class="space-y-2">
      <input type="hidden" name="entry_id" value={@entry.id} />
      <.input
        id={"lyrics-paste-text-#{@entry.id}"}
        name="lrc_text"
        type="textarea"
        label="Paste .lrc"
        value=""
      />
      <.button type="submit">Save pasted lyrics</.button>
    </.form>
    """
  end

  attr :class, :any, default: nil

  defp host_badge(assigns) do
    ~H"""
    <span class={[
      "rounded-full border border-amber-200/30 px-2 py-0.5 uppercase tracking-wider text-amber-100",
      @class
    ]}>
      Host
    </span>
    """
  end

  defp playback_heading(%{title: title} = playback) when is_binary(title) and title != "" do
    Catalog.format_title(title, Map.get(playback, :artist))
  end

  defp playback_heading(_), do: "Nothing yet — host can start the singer or demo track"

  defp playback_empty?(nil), do: true
  defp playback_empty?(%{title: title}) when is_binary(title) and title != "", do: false
  defp playback_empty?(_), do: true

  defp playback_mode(%{mode: :singing}), do: :singing
  defp playback_mode(_), do: nil

  defp playback_mode_label(%{mode: :singing}), do: "Singer (backing track)"

  defp stem_progress_label(%{stem_status: :queued}), do: "Waiting for your Mac to remove vocals…"

  defp stem_progress_label(%{stem_status: :running, stem_progress: pct}) when is_integer(pct) do
    "Removing vocals #{pct}%"
  end

  defp stem_progress_label(_), do: "Removing vocals…"

  defp offset_label(nil), do: "Lyrics on time"
  defp offset_label(0), do: "Lyrics on time"

  defp offset_label(ms) when is_integer(ms) and ms > 0 do
    "Lyrics #{format_offset(ms)} earlier"
  end

  defp offset_label(ms) when is_integer(ms) do
    "Lyrics #{format_offset(-ms)} later"
  end

  defp format_offset(ms) when rem(ms, 1000) == 0, do: "#{div(ms, 1000)}s"
  defp format_offset(ms), do: "#{Float.round(ms / 1000, 1)}s"

  defp status_label(:requested), do: "Requested"
  defp status_label(:preparing), do: "Preparing"
  defp status_label(:ready), do: "Ready"
  defp status_label(:now_singing), do: "Now singing"
  defp status_label(:done), do: "Done"
  defp status_label(other), do: to_string(other)

  defp stem_retry_label(song) do
    if Catalog.stem_failed?(song), do: "Retry", else: "Remove vocals"
  end

  defp all_upload_errors(upload) do
    upload_errors(upload) ++
      Enum.flat_map(upload.entries, &upload_errors(upload, &1))
  end

  defp upload_error_text(:too_large), do: "That file is too large"
  defp upload_error_text(:not_accepted), do: "Unsupported audio type"
  defp upload_error_text(:too_many_files), do: "Only one file at a time"
  defp upload_error_text(_), do: "Upload failed"
end
