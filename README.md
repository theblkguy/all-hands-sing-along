# All Hands Sing Song

Karaoke companion for all-hands: Zoom is for faces, this app syncs a backing track, timed lyrics, and a singer queue.

One person **hosts on a Mac**. Everyone else opens the same room on their phone or laptop so the song and lyrics stay in sync. Stay on Zoom for faces. Use headphones so the backing track does not leak into the call.

This guide is for hosting on macOS. You do not need Postgres — the app uses a local SQLite file.

To put the app on the public internet instead, see [Deploy on Fly.io](#deploy-on-flyio). The Fly machine stays small (no Demucs). For automatic vocal isolation on the hosted site, run `mix stems.worker` on your Mac.

## What you need

- A Mac on the same Wi-Fi as your guests
- About 15–30 minutes the first time (mostly downloads)
- An internet connection (lyrics lookup and the first vocal-isolation model)

Typical all-hands flow:

1. You start the app on this Mac and create a room.
2. You share the URL and room code.
3. People add songs to the queue (mp3 / wav / m4a / ogg, optional `.lrc` lyrics).
4. You hit **Play**. Everyone’s lyrics stay in sync. Zoom stays for video.

## 1. Install Homebrew

If `brew` is already available (`brew --version`), skip this.

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

On Apple Silicon, follow the “Next steps” Homebrew prints so `brew` is on your PATH (usually adding it to `~/.zprofile`). Then open a new Terminal window.

Confirm:

```sh
brew --version
```

If compilation later fails, install Apple’s command line tools:

```sh
xcode-select --install
```

## 2. Install Elixir, ffmpeg, and Python

```sh
brew install elixir ffmpeg python git
```

- **Elixir** (1.17+) includes Erlang and is what runs the app.
- **ffmpeg** is required for vocal isolation.
- **Python** is required for [Demucs](https://github.com/facebookresearch/demucs), which strips vocals from uploaded songs. Do not use macOS’s `/usr/bin/python3` — it has no `pip`.

Confirm versions:

```sh
elixir -v          # Elixir 1.17 or newer
which python3      # should be /opt/homebrew/bin/python3 (Apple Silicon)
                   # or /usr/local/bin/python3 (Intel)
ffmpeg -version
```

If `which python3` still prints `/usr/bin/python3`, use the Homebrew path in the next step (`/opt/homebrew/bin/python3` or `/usr/local/bin/python3`).

## 3. Get the project

If you already have the folder, `cd` into it. Otherwise:

```sh
git clone <this-repo-url>
cd all_hands_sing_along
```

## 4. Install vocal isolation (Demucs)

Uploaded songs stay **Preparing** until an instrumental exists and timed lyrics are attached. Isolation runs locally with Demucs (`--two-stems=vocals`). It is slow (often a few minutes per song) and needs a one-time model download the first time you process a track.

Homebrew Python will refuse a system-wide `pip install`, so use a project virtualenv:

```sh
cd all_hands_sing_along

# Apple Silicon
/opt/homebrew/bin/python3 -m venv .venv

# Intel Macs, if the line above fails:
# /usr/local/bin/python3 -m venv .venv

.venv/bin/python -m pip install --upgrade pip
.venv/bin/python -m pip install demucs numpy
```

Confirm:

```sh
.venv/bin/python -c "import demucs; print('demucs ok')"
```

The app looks for `.venv/bin/python` automatically. Restart `mix phx.server` after you install Demucs if the server is already running.

If Demucs is missing, the queue shows **Vocal isolation isn’t installed on this machine**. You can still **Attach instrumental**, **Retry**, or **Use original anyway**.

Lyrics lookup is separate: a missing LRC still shows **Couldn't find timed lyrics** even while vocals are being removed.

## 5. Install the Elixir app

From the project root:

```sh
mix setup
```

The first run downloads Hex packages, creates `all_hands_sing_along_dev.db`, and builds JS/CSS. That can take a few minutes.

If Mix asks to install Hex or Rebar, say yes.

## 6. Start the server

```sh
mix phx.server
```

Leave this Terminal window open. The Mac is the karaoke machine — if you quit the server, the room goes away for everyone.

Find this Mac’s Wi-Fi address:

```sh
ipconfig getifaddr en0
```

If that prints nothing, try `en1` (common on Macs using Ethernet or a USB adapter):

```sh
ipconfig getifaddr en1
```

On this Mac, open [http://localhost:4000](http://localhost:4000).

Guests should use `http://YOUR_IP:4000` — for example `http://192.168.1.42:4000`. They will not be able to use `localhost`; that only works on the host Mac.

The server listens on the local network by default (`0.0.0.0`). If macOS asks whether Terminal / beam / Elixir may accept incoming connections, choose **Allow**.

### macOS Firewall

If guests cannot load the page:

1. System Settings → Network → Firewall
2. Allow incoming connections for the Erlang/Elixir process, or turn the firewall off for the session
3. Confirm guests are on the **same Wi-Fi**, not guest/isolated/VPN Wi-Fi
4. Confirm you shared `http://IP:4000`, not `https`

## 7. Host a karaoke session

On the host Mac (use this same browser for the whole session — the host cookie lives there):

1. Open `http://localhost:4000`.
2. Under **Host a room**, enter your name and click **Create room**.
3. You should see a **Host** badge, Play / Pause / Skip, and a short room code.
4. Share with the group:
   - The URL: `http://YOUR_IP:4000`
   - The **room code** on screen
5. Guests open that URL, enter their name and the room code, then **Join**.
6. Anyone can add a song (title + artist, optional audio file and `.lrc`). The app tries to fetch timed lyrics from [lrclib.net](https://lrclib.net).
7. Wait until a song is **Ready** (instrumental + lyrics). Isolation can take several minutes; the first song also downloads the Demucs model.
8. Host hits **Play**. Everyone should hear the backing track and see the current lyric line.
9. Use **Lyrics later** / **Lyrics earlier** if the line is off by a beat. Reorder ready songs with **Move up** / **Move down**.

### Host checklist

- Keep the Terminal running `mix phx.server` and keep the host browser tab open.
- Use **headphones**. The room page warns about this so Zoom does not pick up the track.
- Stay on Zoom (or Meet) for faces only.
- Do not clear this site’s cookies mid-session or you will lose host controls. Create the room again if that happens.
- Prevent sleep: System Settings → Displays → Advanced → prevent automatic sleeping while the display is off — or plug in and keep the lid open.

### If a song is stuck on Preparing

- **No song file yet** — upload mp3 / wav / m4a / ogg (host can attach audio for anyone; guests can attach their own).
- **Couldn't find timed lyrics** — search with a fuller title, pick a result, or paste an `.lrc`.
- **Removing vocals…** — wait, or **Cancel** / **Use original anyway**.
- **Vocal isolation isn’t installed** — finish [step 4](#4-install-vocal-isolation-demucs) and restart the server.
- Host can **Attach instrumental** if you already have a karaoke/instrumental file.

## Stop / start next time

```sh
cd all_hands_sing_along
mix phx.server
```

You do not need `mix setup` or the Demucs install again unless you deleted the folder or `.venv`.

To stop the server: focus the Terminal window and press `Ctrl+C`.

## Deploy on Fly.io

Phoenix LiveView needs a persistent VM, so this app is not a fit for Vercel. [Fly.io](https://fly.io) is the cheapest typical host: one small machine plus a SQLite volume, about **$4–8/month**.

Cloud machines do **not** run Demucs. Songs stay playable if someone attaches an instrumental or uses **Use original anyway**. To strip vocals automatically, leave the cheap Fly app as-is and run Demucs on your Mac with `mix stems.worker` (below).

### 1. Install the Fly CLI and log in

```sh
brew install flyctl
fly auth login
```

### 2. Create the app and volume

`fly.toml` ships with app name `all-hands-sing-along` and region `iad`. If the name is taken, pick another:

```sh
fly apps create your-unique-name
```

Then set `app` and `PHX_HOST` (e.g. `your-unique-name.fly.dev`) in `fly.toml`. Create a 3 GB volume in the same region:

```sh
fly volumes create data --size 3 --region iad --app your-unique-name
```

Skip `--app` if you kept the default name.

### 3. Set the secret and deploy

```sh
fly secrets set SECRET_KEY_BASE="$(mix phx.gen.secret)"
fly deploy
```

The image is a Phoenix release (Elixir + SQLite). It does not install Python, Demucs, or ffmpeg.

Open `https://<app>.fly.dev`. Create a room as host, share that URL and the room code. The machine auto-stops when idle and starts on the next visit (a few seconds of cold start). During a session, LiveView connections keep it running.

If you use a custom domain, set `PHX_HOST` to that domain in `fly.toml` (or `fly secrets` / `[env]`) so LiveView WebSockets pass the origin check.

### 4. Strip vocals from your Mac

The hosted site queues isolation jobs. Your computer downloads each song, runs Demucs, and uploads the instrumental. The Mac must stay awake with this process running.

One-time token (save the printed value):

```sh
TOKEN="$(mix phx.gen.secret)"
echo "$TOKEN"
fly secrets set STEM_WORKER_TOKEN="$TOKEN"
```

Then deploy so Fly has the new worker routes (`fly deploy`).

Before karaoke, in the project folder on your Mac (with `.venv` and Demucs already installed):

```sh
export STEM_WORKER_TOKEN="the-token-from-above"
mix stems.worker
```

Leave that Terminal open. Songs on the website will show **Waiting for your Mac** until this process picks them up. Isolation still takes a few minutes per song.

Optional: `STEM_SITE_URL=https://your-app.fly.dev mix stems.worker` if the app name is not `all-hands-sing-along`.

### 5. Useful commands

```sh
fly status
fly logs
fly ssh console
```

To stop spending money: `fly apps destroy <app-name>` (this deletes the volume too).

## Troubleshooting

| Problem | What to try |
| --- | --- |
| `elixir: command not found` | `brew install elixir`, then open a new Terminal |
| `mix setup` fails compiling | `xcode-select --install`, then retry |
| `which python3` is `/usr/bin/python3` | Create the venv with `/opt/homebrew/bin/python3` (or `/usr/local/bin/python3` on Intel) |
| Queue says isolation isn’t installed | Recreate `.venv`, `pip install demucs numpy`, restart `mix phx.server` |
| Hosted site waits on your Mac | Run `mix stems.worker` with `STEM_WORKER_TOKEN`; Mac must stay awake |
| Guests cannot open the URL | Same Wi-Fi, `ipconfig getifaddr en0`, allow firewall, use `http://IP:4000` |
| Guests see a different room / not host | Only the Mac that clicked **Create room** is host. Guests must **Join** with the code |
| Lyrics never appear | Need internet to lrclib.net, or paste an `.lrc` |
| First song takes forever | Normal. Demucs is downloading its model, then processing on CPU |

## Optional: developers

```sh
mix phx.server              # or: iex -S mix phx.server
mix stems.worker            # Demucs on this Mac for the hosted Fly site
mix test
mix precommit               # compile, format, test
```
