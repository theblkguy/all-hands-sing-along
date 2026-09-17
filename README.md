# All Hands Sing Song

Karaoke for the all-hands. Zoom is still the call. This page keeps the track, lyrics, and queue together.

One person **hosts**. Everyone else opens the same room. Wear headphones so the mix doesn't leak into Zoom.

Live site: [all-hands-sing-along.fly.dev](https://all-hands-sing-along.fly.dev)

**Nobody clones this repo to sing or to host.** Open the URL, type a name, and go. Vocal removal runs in the cloud (Replicate) and finished instrumentals are cached by file hash, so the second time anyone anywhere queues the same track it's instant.

| You are                     | What you install                                                    |
| --------------------------- | ------------------------------------------------------------------- |
| Joining a room              | Nothing — just a browser.                                           |
| Hosting on the live site    | Nothing — just a browser.                                           |
| Running the app on your Mac | Homebrew + this repo once, then `./script/server`                   |
| Deploying your own copy     | Fly CLI + a Replicate API token (see [Deploy on Fly.io](#deploy-on-flyio)) |

This guide is for macOS. The app uses SQLite — you do not need Postgres.

---

## Use the live site

Guests: open [all-hands-sing-along.fly.dev](https://all-hands-sing-along.fly.dev), sign in, enter the room code, click **Join**. That is the whole setup.

Hosts: under **Host a room**, click **Create room**. Share the room code. When a song is **Ready**, hit **Play**.

### Sign in

The live site asks for your Google account (restricted to the company domain). After the first sign-in, pick a username — that's what the room shows. You can change it later on the home page.

### Keep your host controls

If you created the room while signed in, you're the host from any browser you sign into — phone, laptop, incognito. The host link below is for handing the controls to a co-host.

The room page has a **Show host link** button. Save that link. Opening it in any browser — your phone, a second laptop, after clearing cookies — makes that browser the host. Don't paste it in the Zoom chat; anyone with it can drive the room.

### How vocal removal works now

- Upload an mp3/wav/m4a/ogg with your song. The server hashes the file and checks the **stem cache** first. If anyone has ever separated that exact file, the instrumental is attached immediately.
- Otherwise the server hands a signed URL to **Replicate**, which runs Demucs on a GPU (roughly a minute, a couple of cents). The result gets a quiet guide vocal mixed in, is stored in Tigris, and is written to the cache for next time.
- No Mac worker, no Terminal. If the deployment has no `REPLICATE_API_TOKEN`, the app falls back to the old behaviour and the room page shows the **Show Mac command** hint again (see [Mac worker fallback](#mac-worker-fallback)).

You can still skip separation for any song: attach a karaoke file, or **Play original**.

---

## Run it locally

For developers, or an office with no internet you trust. After `./script/setup`, this computer **is** the karaoke server.

Install Homebrew first if `brew --version` doesn't work:

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

On Apple Silicon, follow Homebrew's "Next steps" so `brew` is on your PATH, then open a new Terminal. Then:

```sh
git clone https://github.com/theblkguy/all-hands-sing-along.git
cd all-hands-sing-along
./script/setup
```

That installs Homebrew Python, Demucs, ffmpeg, and Elixir into this folder. Safe to re-run. Elixir and OTP versions are pinned in `.tool-versions` (asdf: Erlang 27.3, Elixir 1.18.4).

Locally there's no sign-in unless you export `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` (redirect URI `http://localhost:4000/auth/google/callback`).

Vocal removal locally uses the Demucs that setup installed. To use Replicate instead (faster, no model download), `export REPLICATE_API_TOKEN=r8_...` before starting the server; local files are uploaded to Replicate for you.

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

- Keep the host browser tab open. Running locally, keep the server Terminal running too.
- Wear headphones. Zoom (or Meet) is for faces.
- Save your host link (or sign in) so you can get host controls back if you lose the tab or clear cookies.
- Prevent sleep, or plug in and keep the lid open.

### If a song is stuck on Preparing

- **No audio yet** — upload mp3 / wav / m4a / ogg.
- **No timed lyrics** — try a fuller title, pick a result, or paste an `.lrc`.
- **Waiting to remove vocals…** — Replicate is queued; usually under a minute. **Waiting on your Mac…** means this deploy has no Replicate token and needs the Mac worker.
- **Removing vocals…** — wait, or **Cancel** / **Play original**.
- If you already have a karaoke file, upload it and **Play original**.

---

## Deploy on Fly.io

The Fly machine does not run Demucs itself; it calls Replicate. Nobody runs anything on a Mac.

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
fly secrets set REPLICATE_API_TOKEN="r8_..."
fly deploy
```

`REPLICATE_API_TOKEN` comes from [replicate.com/account](https://replicate.com/account). Without it the app still deploys, but vocal removal falls back to the [Mac worker](#mac-worker-fallback).

Open `https://<app>.fly.dev`. Create a room as host, share that URL and the room code, and save your host link.

If you use a custom domain, set `PHX_HOST` to that domain in `fly.toml`.

### 5. Sign in with Google (optional)

Skip this and the site stays open to anyone with the URL. To limit it to your company:

1. In Google Cloud console, create an OAuth client of type **Web application**.
2. Add `https://<app>.fly.dev/auth/google/callback` as an authorized redirect URI (use your custom domain if you set `PHX_HOST`).
3. Set the secrets and redeploy:

```sh
fly secrets set GOOGLE_CLIENT_ID="..." GOOGLE_CLIENT_SECRET="..." GOOGLE_ALLOWED_DOMAINS="yourcompany.com"
fly deploy
```

`GOOGLE_ALLOWED_DOMAINS` is comma-separated and checked server-side, so a personal Gmail account can't get in even if it reaches the consent screen. Leave it unset to accept any Google account.

### Mac worker fallback

Only needed when the deploy has **no** `REPLICATE_API_TOKEN`. In that case the Fly VM can't strip vocals itself, so the host's Mac does it for the host's room only, and the room page shows a **Show Mac command** button.

One-time setup on that Mac (Homebrew, Python, Demucs, ffmpeg, Elixir go into the project folder):

```sh
git clone https://github.com/theblkguy/all-hands-sing-along.git
cd all-hands-sing-along
./script/setup
```

Each session: create the room, click **Show Mac command**, and run it from the `all-hands-sing-along` folder. Leave that Terminal open and keep the Mac awake. It looks like:

```sh
./script/worker --room ABC123 --token YOUR_HOST_TOKEN
```

If the app name is not `all-hands-sing-along`, pass the URL too:

```sh
./script/worker --room … --token … --url https://your-app.fly.dev
```

The first song of the day can take several minutes while Demucs downloads its model and runs on CPU.

### 6. Useful commands

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
| Guests see a different room / not host | Host is the browser that clicked **Create room**, opened the host link, or is signed in as the room's owner. Guests must **Join** with the code |
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
