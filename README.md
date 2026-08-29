# All Hands Sing Song

Karaoke companion for all-hands: Zoom is for faces, this app syncs a backing track, timed lyrics, and a singer queue.

One person **hosts**. Everyone else opens the same room so the song and lyrics stay in sync. Stay on Zoom for faces. Use headphones so the backing track does not leak into the call.

This guide is for macOS. You do not need Postgres — the app uses a local SQLite file.

To put the app on the public internet, see [Deploy on Fly.io](#deploy-on-flyio). The Fly machine stays small (no Demucs). Each host runs vocal isolation on **their own Mac** for **their own room**.

## What you need

- A Mac
- About 15–30 minutes the first time (mostly downloads)
- An internet connection (lyrics lookup and the first vocal-isolation model)

Typical all-hands flow:

1. You create a room (on Fly or on this Mac).
2. You share the URL and room code.
3. People add songs to the queue (mp3 / wav / m4a / ogg, optional `.lrc` lyrics).
4. You hit **Play**. Everyone’s lyrics stay in sync. Zoom stays for video.

## 1. Install Homebrew

If `brew` is already available (`brew --version`), skip this.

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

On Apple Silicon, follow the “Next steps” Homebrew prints so `brew` is on your PATH. Then open a new Terminal window.

If compilation later fails: `xcode-select --install`.

## 2. Get the project and install everything

```sh
git clone <this-repo-url>
cd all_hands_sing_along
./script/setup
```

That installs Elixir, ffmpeg, Python, Demucs, and the Phoenix app. Safe to re-run.

## 3. Start

**Hosted site** ([all-hands-sing-along.fly.dev](https://all-hands-sing-along.fly.dev)): create a room as host. The page shows a command that only processes **your** room:

```sh
./script/worker --room ABC123 --token YOUR_HOST_TOKEN
```

Leave that window open. Another host on the same site uses **their** command; workers do not share a queue. Guests never need a token. You can still **Attach instrumental** or **Use original anyway**. Isolation can take several minutes; the first song also downloads the Demucs model.

**Local Wi-Fi** (this Mac is the karaoke server):

```sh
./script/server
```

On this Mac, open [http://localhost:4000](http://localhost:4000). Leave the Terminal open.

Find this Mac’s Wi-Fi address:

```sh
ipconfig getifaddr en0
```

If that prints nothing, try `en1`. Guests use `http://YOUR_IP:4000` — not `localhost`. If macOS asks to accept incoming connections, choose **Allow**.

### macOS Firewall

If guests cannot load the page:

1. System Settings → Network → Firewall
2. Allow incoming connections for the Erlang/Elixir process, or turn the firewall off for the session
3. Confirm guests are on the **same Wi-Fi**, not guest/isolated/VPN Wi-Fi
4. Confirm you shared `http://IP:4000`, not `https`

## 4. Host a karaoke session

Use the same browser for the whole session — the host cookie lives there.

1. Open the site (Fly URL or `http://localhost:4000`).
2. Under **Host a room**, enter your name and click **Create room**.
3. You should see a **Host** badge, Play / Pause / Skip, and a short room code.
4. Share the URL and the **room code**.
5. Guests enter their name and the room code, then **Join**.
6. Anyone can add a song. The app tries to fetch timed lyrics from [lrclib.net](https://lrclib.net).
7. Wait until a song is **Ready** (instrumental + lyrics).
8. Host hits **Play**.
9. Use **Lyrics later** / **Lyrics earlier** if the line is off. Reorder ready songs with **Move up** / **Move down**.

### Host checklist

- Keep the worker or server Terminal running, and keep the host browser tab open.
- Use **headphones**.
- Stay on Zoom (or Meet) for faces only.
- Do not clear this site’s cookies mid-session or you will lose host controls.
- Prevent sleep, or plug in and keep the lid open.

### If a song is stuck on Preparing

- **No song file yet** — upload mp3 / wav / m4a / ogg.
- **Couldn't find timed lyrics** — search with a fuller title, pick a result, or paste an `.lrc`.
- **Waiting for your Mac** — run the host command from the room page (`./script/worker …`).
- **Removing vocals…** — wait, or **Cancel** / **Use original anyway**.
- Host can **Attach instrumental** if you already have a karaoke file.

## Stop / start next time

```sh
cd all_hands_sing_along
./script/setup          # only if you deleted .venv or the folder
./script/worker --room … --token …   # Fly
# or
./script/server                      # local Wi-Fi
```

To stop: focus the Terminal window and press `Ctrl+C`.

## Deploy on Fly.io

Phoenix LiveView needs a persistent VM, so this app is not a fit for Vercel. [Fly.io](https://fly.io) is the cheapest typical host: one small machine plus a SQLite volume, about **$4–8/month**.

Cloud machines do **not** run Demucs. Each host isolates vocals on their Mac with `./script/worker`. Songs stay playable if someone attaches an instrumental or uses **Use original anyway**.

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

Open `https://<app>.fly.dev`. Create a room as host, share that URL and the room code. Copy the **vocal isolation** command from the room page and run it on your Mac. The machine auto-stops when idle and starts on the next visit.

If you use a custom domain, set `PHX_HOST` to that domain in `fly.toml` so LiveView WebSockets pass the origin check.

Optional: `./script/worker --room … --token … --url https://your-app.fly.dev` if the app name is not `all-hands-sing-along`.

### 4. Useful commands

```sh
fly status
fly logs
fly ssh console
```

To stop spending money: `fly apps destroy <app-name>` (this deletes the volume too).

## Troubleshooting

| Problem | What to try |
| --- | --- |
| `elixir: command not found` | `./script/setup`, then open a new Terminal |
| `mix setup` fails compiling | `xcode-select --install`, then `./script/setup` |
| Demucs missing | `./script/setup` (uses Homebrew Python, not `/usr/bin/python3`) |
| Hosted site waits on your Mac | Run the command on the room page; Mac must stay awake |
| Wrong room’s songs processing | Each host must use **their** `--room` and `--token` |
| Guests cannot open the URL | Same Wi-Fi, `ipconfig getifaddr en0`, allow firewall, use `http://IP:4000` |
| Guests see a different room / not host | Only the browser that clicked **Create room** is host. Guests must **Join** with the code |
| Lyrics never appear | Need internet to lrclib.net, or paste an `.lrc` |
| First song takes forever | Normal. Demucs is downloading its model, then processing on CPU |

## Optional: developers

```sh
./script/setup
./script/server
./script/worker --room CODE --token TOKEN
mix test
mix precommit
```
