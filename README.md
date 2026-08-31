# All Hands Sing Song

Karaoke companion for all-hands. Zoom is for faces. This app syncs a backing track, timed lyrics, and a singer queue.

One person **hosts**. Everyone else opens the same room. Use headphones so the mix does not leak into the call.

Live site: [all-hands-sing-along.fly.dev](https://all-hands-sing-along.fly.dev)

**Singers never clone this repo.** They open the URL, type a name and room code, and join. Only the host installs anything, and only if they want the Mac to strip vocals.

| You are | What you install |
| --- | --- |
| Joining a room | Nothing. A browser. |
| Hosting on the live site | Homebrew + this repo once, so Demucs can strip vocals |
| Running the app on your Mac | Same one-time setup, then `./script/server` |

This guide is for macOS. The app uses SQLite — you do not need Postgres.

---

## Use the live site

Guests: open [all-hands-sing-along.fly.dev](https://all-hands-sing-along.fly.dev), enter your name and the room code, click **Join**. That is the whole setup.

### Host: strip vocals with Demucs

The live site does not run Demucs (it is too heavy for a small cloud VM). **Your Mac** does it, for **your room only**. One-time install, about 15–30 minutes. After that, each session is one Terminal command.

You can skip this and still host: attach a karaoke file, or use **Use original anyway**.

#### 1. Homebrew (skip if `brew --version` works)

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

On Apple Silicon, follow Homebrew’s “Next steps” so `brew` is on your PATH, then open a new Terminal.

#### 2. Clone once and run setup

```sh
git clone https://github.com/theblkguy/all-hands-sing-along.git
cd all-hands-sing-along
./script/setup
```

That installs Homebrew Python, Demucs, ffmpeg, and Elixir into this folder. Safe to re-run. If it says `mix` was not found, open a **new** Terminal so Elixir is on your PATH, then run `./script/setup` again.

Elixir and OTP versions are pinned in `.tool-versions` (asdf: Erlang 27.3, Elixir 1.18.4). The Dockerfile uses the same pair.

Nobody else in the all-hands does this. One Mac, one clone.

#### 3. Create a room, then start the worker

1. Open the [live site](https://all-hands-sing-along.fly.dev) and **Create room**.
2. Copy the command shown on the room page (click **Show Mac worker command**). It looks like:

```sh
./script/worker --room ABC123 --token YOUR_HOST_TOKEN
```

3. Run it from the `all-hands-sing-along` folder. Leave that window open while people sing.

The worker only processes **your** room. Another host on the same site runs their own command. Guests never need a token.

First song of the day can take several minutes (Demucs downloads its model, then runs on CPU). After that, leave Terminal open and keep the Mac awake.

Next session: `cd all-hands-sing-along` and run the new room’s worker command. Re-run `./script/setup` only if you deleted `.venv` or the folder.

---

## Run it locally

Same Mac setup as above. After `./script/setup`, this computer **is** the karaoke server. Demucs runs here automatically — you do not need `./script/worker`.

```sh
git clone https://github.com/theblkguy/all-hands-sing-along.git
cd all-hands-sing-along
./script/setup
```

If setup asked you to open a new Terminal for `mix`, do that and re-run `./script/setup`. Then:

```sh
./script/server
```

On this Mac, open [http://localhost:4000](http://localhost:4000). Leave the Terminal open.

### Share it on Wi-Fi

Find this Mac’s address:

```sh
ipconfig getifaddr en0
```

If that prints nothing, try `en1`. Guests use `http://YOUR_IP:4000` — not `localhost`, not `https`. If macOS asks to accept incoming connections, choose **Allow**.

Everyone must be on the **same Wi-Fi** (not guest/isolated/VPN Wi-Fi). If they still cannot load the page: System Settings → Network → Firewall, then allow the Erlang/Elixir process (or turn the firewall off for the session).

To stop: focus the Terminal window and press `Ctrl+C`. Next time: `cd all-hands-sing-along` and `./script/server`.

---

## Host a karaoke session

Use the same browser for the whole session — the host cookie lives there.

1. Open the site (live URL or `http://localhost:4000`).
2. Under **Host a room**, enter your name and click **Create room**.
3. You should see a **Host** badge, Play / Pause / Skip, and a short room code.
4. Share the URL and the **room code**. Guests enter their name and the code, then **Join**.
5. Anyone can add a song (mp3 / wav / m4a / ogg, optional `.lrc`). The app tries to fetch timed lyrics from [lrclib.net](https://lrclib.net).
6. Wait until a song is **Ready** (instrumental + lyrics).
7. Host hits **Play**.
8. Use **Lyrics later** / **Lyrics earlier** if the line is off. Reorder ready songs with **Move up** / **Move down**.

### Host checklist

- Keep the worker (live site) or server (local) Terminal running, and keep the host browser tab open.
- Headphones on. Zoom (or Meet) for faces only.
- Do not clear this site’s cookies mid-session or you will lose host controls.
- Prevent sleep, or plug in and keep the lid open.

### If a song is stuck on Preparing

- **No song file yet** — upload mp3 / wav / m4a / ogg.
- **Couldn't find timed lyrics** — search with a fuller title, pick a result, or paste an `.lrc`.
- **Waiting for your Mac** — run the host command from the room page (`./script/worker …`).
- **Removing vocals…** — wait, or **Cancel** / **Use original anyway**.
- Host can **Attach instrumental** if you already have a karaoke file.

---

## Deploy on Fly.io

The Fly machine does not run Demucs. After deploy, each host still runs `./script/worker` on their Mac.

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

### 3. Object storage (Tigris)

Audio should not live on the Fly volume. Create a Tigris bucket (sets AWS_* secrets on the app):

```sh
fly storage create
```

That provides `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_ENDPOINT_URL_S3`, `AWS_REGION`, and `BUCKET_NAME`. The app uses those at runtime. The `/data` volume stays for SQLite only.

### 4. Set the secret and deploy

```sh
fly secrets set SECRET_KEY_BASE="$(mix phx.gen.secret)"
fly deploy
```

Open `https://<app>.fly.dev`. Create a room as host, share that URL and the room code, then run the vocal isolation command from the room page on your Mac.

If you use a custom domain, set `PHX_HOST` to that domain in `fly.toml`.

If the app name is not `all-hands-sing-along`, pass the URL to the worker:

```sh
./script/worker --room … --token … --url https://your-app.fly.dev
```

### 5. Useful commands

```sh
fly status
fly logs
fly ssh console
```

---

## Troubleshooting

| Problem | What to try |
| --- | --- |
| `elixir: command not found` / `mix was not found` | `./script/setup`, then open a new Terminal so Elixir is on your PATH |
| `mix setup` fails compiling | `xcode-select --install`, then `./script/setup` |
| Demucs missing / worker says run setup | `./script/setup` (Homebrew Python into `.venv`, not `/usr/bin/python3`) |
| `ffmpeg` missing / “needs ffmpeg to mix a quiet guide vocal” | `brew install ffmpeg`, or re-run `./script/setup` |
| Hosted site waits on your Mac | Run the command on the room page; Mac must stay awake |
| Wrong room’s songs processing | Each host must use **their** `--room` and `--token` |
| Guests cannot open the local URL | Same Wi-Fi, `ipconfig getifaddr en0`, allow firewall, use `http://IP:4000` |
| Guests see a different room / not host | Only the browser that clicked **Create room** is host. Guests must **Join** with the code |
| Lyrics never appear | Need internet to lrclib.net, or paste an `.lrc` |
| First song takes forever | Normal. Demucs is downloading its model, then processing on CPU |

---

## Developers

How the pieces fit: [ARCHITECTURE.md](ARCHITECTURE.md).

```sh
./script/setup
./script/server
./script/worker --room CODE --token TOKEN
mix test
mix precommit
```
