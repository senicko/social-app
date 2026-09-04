# Cloud agent workflow: EAS build, Argent Cloud simulator, mock backend, before/after PR

A Cursor Cloud agent clones this repo, builds the iOS dev client on EAS, leases a macOS runner from Argent Cloud with `sim-remote`, installs the app on that runner's simulator, serves JavaScript to it from Metro running in the cloud VM against a local mock Bluesky network, makes a code change, records before and after videos, and opens a pull request whose description has a Before/After table with the videos attached.

Everything the coordinating prompt must spell out is here. Section 3 is the runbook; section 4 is a paste-ready prompt. The files that implement section 2 live under `.cursor/`.

---

## 0. The shape of the system

```
+---------------------------- Cursor Cloud VM (Ubuntu) -----------------------------+
|  cloned repo    Metro :8081    eas-cli    gh    ffmpeg                             |
|  mock Bluesky network: Postgres :5433, Redis :6380, dev-env mock server            |
|      manager :1986 (seeds alice/bob/carla), PDS :3000, appview + PLC              |
|  argent tool-server (local)  <-- MCP tools the agent calls                         |
|  sim-remote daemon           <-- session, machine lease, tunnels                   |
+------------------------------------------------------------------------------------+
            |  sim-remote (QUIC)                 ^  reverse 8081 (Metro)
            v                                   ^  reverse 3000 (mock PDS)
+--------------------------- Argent Cloud macOS runner ------------------------------+
|  iOS simulators (leased to this session)                                            |
|  argent simulator-server injected by argent over the sim-remote transport           |
+------------------------------------------------------------------------------------+
```

Five facts drive the design:

1. **`sim-remote` is the whole networking story.** `sim-remote login` leases a macOS runner; `sim-remote simctl ...` is a drop-in `xcrun simctl`; file arguments are local paths that get uploaded (`install`) or downloaded (`io screenshot`, `io recordVideo`); `sim-remote reverse start <UDID> <port>` lets the simulator reach a listener on the VM at its own `localhost:<port>`. Two tunnels: 8081 for Metro, 3000 for the mock PDS.
2. **Argent already speaks sim-remote.** With `sim-remote` on `PATH` and a session open, argent's `list-devices` returns the runner's simulators as `platform: "ios-remote"`, and the normal toolkit (`describe`, `gesture-tap`, `keyboard`, `paste`, `screenshot`, `launch-app`, `open-url`, `reinstall-app`, `await-ui-element`, `debugger-*`) works on them.
3. **The backend is the repo's own mock network, on the VM.** `dev-env/` (what the Maestro e2e suite uses) runs a real PDS, appview and PLC against Postgres and Redis, seeded with `alice.test`, `bob.test`, `carla.test`, follows, posts and a thread. No Bluesky account, no secrets, no public side effects; the agent may post, like and follow freely. Bluesky's nightly CI runs the same thing on macOS with `pnpm --dir dev-env start:external`; here Postgres and Redis are Ubuntu packages, no Docker.
4. **The app is told which appview to trust at bundle time.** The seed reply carries an `appviewDid`; `mock-backend.sh` writes it into `.env` as `EXPO_PUBLIC_BLUESKY_PROXY_DID` before the Metro terminal starts, because `EXPO_PUBLIC_*` values are inlined into the bundle. In practice the DID is deterministic (`did:plc:bw7ad3erl7btq6qwf66yqiov` on two machines and across reseeds, because dev-env uses fixed keys), but the script rewrites `.env` on every seed and the runbook restarts Metro with `--clear` after a reseed anyway.
5. **Screen recording is the one tool argent does not support on remote simulators.** The runbook records with `sim-remote simctl io <UDID> recordVideo <local.mp4>` through `.cursor/cloud/record.sh`.

---

## 1. One-time human setup

### 1.1 Argent Cloud

- The `sim-remote` binary comes from the public release https://github.com/software-mansion/sim-remote-releases/releases/tag/softu. `.cursor/cloud/ensure-sim-remote.sh` has that release hardcoded, picks the asset for the machine's architecture (`sim-remote-x86_64-unknown-linux-gnu` on Cursor VMs, `sim-remote-aarch64-apple-darwin` on a laptop), installs it and the companion `sim-remote-daemon` into `/usr/local/bin` during `install` and again in `start` if needed. `SIM_REMOTE_DOWNLOAD_URL` overrides the source when set; no secret is required.
- A username and API key for the agent, stored as the secrets `SIM_ROUTER_USERNAME` and `SIM_ROUTER_API_KEY` (the exact names `sim-remote login` reads). The sim-router server URL is baked into the binary (`--server`, env `SIM_ROUTER_URL`, default `https://77.42.125.138:3030` in the `softu` release); set `SIM_ROUTER_URL` only if your fleet moves.
- Fleet etiquette the prompt must enforce: one `login` per run (done by `start.sh`), `stop.sh` at the end, never leave a machine leased. `login` waits for a free runner (`start.sh` uses a 300 s timeout).

### 1.2 Expo / EAS

- `app.config.js` points at your Expo project: `owner`, `slug`, `extra.eas.projectId` (`eas init --id` cannot write to a dynamic config, so this is a manual edit).
- Remote build counters initialized once (`eas build:version:set -p ios`; the repo uses `appVersionSource: remote`).
- Build profile `dev-sim` in `eas.json`: extends `development`, `ios.simulator: true`, `ios.resourceClass: medium` (the upstream `large` needs a paid plan), and `env.EXPO_PUBLIC_ENV: development`. Two things in `app.config.js` depend on that env and were verified with real builds:
  - With `production`, the config bakes expo-updates code signing into the native build and the dev client refuses Metro with `Code signature validation failed: No expo-signature header specified`.
  - With `development`, ccache would be enabled; the wrapper path does not resolve for the extension targets on EAS, so the config uses `ccacheEnabled: IS_DEV && !process.env.EAS_BUILD` (ccache stays on for local `expo run:ios`).
- An expo.dev access token as the `EXPO_TOKEN` secret. The agent builds the dev client on EAS at the start of every run (section 1.7); eas-cli reads `EXPO_TOKEN` and needs nothing else.

### 1.3 GitHub: how git and gh are wired

Two separate credentials are in play, and nothing in the Dockerfile or the scripts configures either:

- **git (clone, fetch, push)** uses Cursor's own GitHub integration. Cursor clones the repo with the GitHub App you authorized when connecting the repository, and the same credential helper serves `git push`. The repo therefore needs to be one that app can write to (a fork of `bluesky-social/social-app` in your account or org).
- **`gh` (PR creation, attachments)** reads the `GH_TOKEN` environment variable automatically; no `gh auth login` step exists or is needed. `GH_TOKEN` is a Cursor secret holding a fine-grained PAT with Contents and Pull requests read/write on that fork. `gh auth status` in step 1 proves it arrived. If you would rather have git pushes use the same PAT instead of Cursor's helper, run `gh auth setup-git` once in `start.sh`; the plan does not, because Cursor's helper already covers pushes.
- **Media in the PR** goes through `gh`'s `--attach` flag (gh 2.99+; the image ships 2.100). `gh pr create --attach ./media/before.mp4 ...` uploads the file as a GitHub user attachment, which is the only kind of video URL GitHub renders inline. Local paths referenced in the body's markdown are rewritten to the uploaded assets; attachments not referenced in the body are appended at the end. Supported: PNG, JPEG, GIF, WebP, SVG, MP4, MOV, WebM. Limits: 10 MB per image, 10 MB per video on Free plans, 100 MB on paid plans. No media branch, no release, nothing committed to git.

### 1.4 The mock Bluesky network (no account needed)

`.cursor/cloud/mock-backend.sh` owns it. `start` creates a dedicated Postgres cluster `bsky` on port 5433 with role `pg` / password `password` (the credentials `dev-env/dev-infra/_common.sh` expects), starts Redis on 6380, runs `node dev-env/mock-server.ts` in the background (log in `.cursor/cloud/mock-server.log`), POSTs `?users&follows&posts&thread&feeds` to the manager on 1986, and writes the returned `appviewDid` into `.env` and into `.cursor/cloud/mock.env` (`MOCK_PDS_URL`, `MOCK_APPVIEW_DID`, `MOCK_USER`). `seed` repeats the POST (the whole network is rebuilt), `status` and `stop` do what they say. `MOCK_SEED` changes the seed query; `dev-env/mock-server.ts` also knows `mergefeed` (many posts, replies and feeds) and `labels` (moderation fixtures).

Users are `alice.test`, `bob.test`, `carla.test`; the password for all of them is the fixture `hunter2` from `dev-env/test-pds.ts`. It is test data, not a secret: the agent types it with `keyboard` like any other text.

Known gaps of the mock appview, so the prompt does not send the agent chasing them: post search returns "Method Not Implemented", Explore's suggested feeds and accounts show "agent not available", and images do not load (the seeded appview advertises port 2584 while listening elsewhere), so avatars are placeholders. Feeds, threads, likes, reposts, profiles, notifications, people search, the composer, settings and the drawer all work.

### 1.5 The branch the agent starts from

Commit to it:

- `package.json` / `pnpm-lock.yaml` with `@swmansion/argent` as a devDependency, and `pnpm-workspace.yaml` with the `allowBuilds` placeholders set to `false` (the literal `set this to true or false` lines break every install).
- `.cursor/mcp.json`, `.cursor/rules/argent.md`, `.claude/rules/argent.md`, `.claude/skills/argent-*`.
- `app.config.js` (EAS owner/slug/projectId, ccache guard) and `eas.json` (`dev-sim`).
- `.cursor/environment.json`, `.cursor/Dockerfile`, `.cursor/cloud/*` and this document.

Never commit `.env`, `google-services.json`, `ios/`, `build/`, `media/`, or anything under `.cursor/cloud/` that the scripts generate (`session.env`, `mock.env`, logs, pid files; all gitignored).

### 1.6 Cursor secrets (Settings > Cloud Agents > Secrets; injected as environment variables)

| Secret                               | Type in Cursor       | Read by                | Notes                                                          |
| ------------------------------------ | -------------------- | ---------------------- | -------------------------------------------------------------- |
| `SIM_ROUTER_USERNAME`                | Environment Variable | `sim-remote login`     | Argent Cloud username.                                         |
| `SIM_ROUTER_API_KEY`                 | Runtime Secret       | `sim-remote login`     | Argent Cloud API key.                                          |
| `EXPO_TOKEN`                         | Runtime Secret       | eas-cli                | EAS build per run, then artifact download.                     |
| `GH_TOKEN`                           | Runtime Secret       | gh                     | PR creation and media upload; git itself uses Cursor's app.    |
| `SIM_REMOTE_DOWNLOAD_URL` (optional) | Environment Variable | `ensure-sim-remote.sh` | Overrides the public release hardcoded in the script.          |
| `SIM_ROUTER_URL` (optional)          | Environment Variable | sim-remote             | Overrides the sim-router URL baked into the binary.            |
| `MOCK_SEED` (optional)               | Environment Variable | `mock-backend.sh`      | Seed query; default `users&follows&posts&thread&feeds`.        |
| `BSKY_DEV_CLIENT_URL` (optional)     | Environment Variable | `get-dev-client.sh`    | Escape hatch: a `.tar.gz` built elsewhere; skips EAS when set. |
| `EAS_PROFILE` (optional)             | Environment Variable | `get-dev-client.sh`    | Profile to build; default `dev-sim`.                           |
| `SIM_DEVICE_NAME` (optional)         | Environment Variable | `start.sh`             | Simulator to use; default `iPhone 17 Pro`.                     |

Cursor offers three types. **Runtime Secret**: loaded as an environment variable for every process, but redacted to `[REDACTED]` in the agent's tool results, transcript and commits; use it for every credential, since gh, eas-cli and sim-remote read the variable themselves and the agent never needs the value. **Environment Variable**: visible to the agent; use it for values the agent has to read and reuse. **Build Secret**: only available inside the Docker image build, not to the agent; none is needed here. Secrets are workspace-scoped and injected at agent start; agents created before a secret existed do not see it.

### 1.7 The dev client is built on EAS every run

The agent has no local copy of the native app, so each run starts with `.cursor/cloud/get-dev-client.sh`: it runs `eas build -p ios --profile dev-sim --no-wait --json`, polls `eas build:view` once a minute until `FINISHED`, downloads `artifacts.buildUrl` and extracts `build/Debug-iphonesimulator/Bluesky.app`. Budget 15 to 25 minutes and one build of the account's EAS quota per run. Two shortcuts exist for when a fresh native build is pointless (the change is JS-only and nothing native moved since the last build): `--reuse-latest` downloads the newest finished `dev-sim` build from EAS, and `BSKY_DEV_CLIENT_URL` downloads a tarball from anywhere. The prompt decides which mode the agent may use.

### 1.8 Register the argent MCP server for cloud agents (required)

Cloud agents do not start MCP servers from the repo. Verified on the first real run: with `.cursor/mcp.json` committed, argent 0.24.0 on `PATH` and the package under `node_modules`, the agent still saw only Cursor's built-in tools (`cursor-cloud`, `cursor-subscriptions`). That matches the docs, which route cloud-agent MCP through the dashboard only: "Add and enable personal MCP servers through the MCP dropdown in cursor.com/agents. Team admins configure shared servers under Dashboard -> Integrations & MCP." (The second exists only on team plans.) `.cursor/environment.json` cannot define a server either: its schema (cursor.com/schemas/environment.schema.json) only has the policy fields `disableAllMcpServers` and `mcpServerAllowlist`, which restrict the user and team servers an environment may use; leave both unset so the personal argent server is allowed. The repo's `.cursor/mcp.json` stays for the desktop IDE.

Register argent once, as a **stdio** server, from the MCP dropdown at cursor.com/agents:

| Field   | Value    |
| ------- | -------- |
| Name    | `argent` |
| Command | `argent` |
| Args    | `mcp`    |

The image installs `@swmansion/argent` globally, so the command resolves from `PATH` whatever working directory Cursor gives the MCP process. Then start a **new** agent: servers are attached when an agent starts, and Cursor says it "cannot verify that a stdio server will run successfully until a cloud agent is launched", so the first run after enabling is the real check. The tool-server the MCP process spawns runs as the same VM user as `start.sh`, so it shares the `sim-remote` session and daemon that `start.sh` opened. Verified in the image: `argent tools` lists the toolkit on Linux, `argent run list-devices` returns an empty list before `sim-remote login` (no crash), and `argent mcp` answers an MCP `initialize` over stdio.

---

## 2. Cursor Cloud environment (files in this repo)

`.cursor/environment.json` (paths in `build` resolve relative to `.cursor/`; Cursor clones the repo after the image is built, so the Dockerfile copies nothing from the repo):

```json
{
  "build": { "dockerfile": "Dockerfile" },
  "install": "bash .cursor/cloud/install.sh",
  "start": "bash .cursor/cloud/start.sh",
  "terminals": [{ "name": "metro", "command": "bash .cursor/cloud/metro.sh" }]
}
```

| File                                 | Runs                   | What it does                                                                                                                                                    |
| ------------------------------------ | ---------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `.cursor/Dockerfile`                 | image build            | Ubuntu 24.04, Node 24, pnpm 11.21, eas-cli, gh 2.99+, argent (global, for the MCP server), ffmpeg, gifsicle, jq, PostgreSQL, Redis; non-root `ubuntu` user with sudo. |
| `.cursor/cloud/install.sh`           | `install` (build time) | `pnpm install --frozen-lockfile` for the app and for `dev-env/`, creates `.env` and `google-services.json` from the examples, installs sim-remote.              |
| `.cursor/cloud/ensure-sim-remote.sh` | install + start        | Fetches sim-remote and sim-remote-daemon for the current architecture from the public release (overridable by `SIM_REMOTE_DOWNLOAD_URL`) into `/usr/local/bin`. |
| `.cursor/cloud/mock-backend.sh`      | start; agent as needed | `services` / `start` / `seed` / `status` / `stop` for Postgres, Redis and the dev-env mock server; writes `EXPO_PUBLIC_BLUESKY_PROXY_DID` into `.env`.          |
| `.cursor/cloud/start.sh`             | `start` (every run)    | `mock-backend.sh start`, then `sim-remote login`, picks and boots the simulator, `reverse start` for 8081 and 3000, writes `.cursor/cloud/session.env`.         |
| `.cursor/cloud/metro.sh`             | terminal `metro`       | `node_modules/expo/bin/cli start --dev-client --port 8081` with `CI=1`; starts after `start.sh`, so it inlines the seeded DID.                                   |
| `.cursor/cloud/get-dev-client.sh`    | agent, step 4          | `eas build --profile dev-sim`, wait, download and extract into `build/`; `--reuse-latest` or `BSKY_DEV_CLIENT_URL` skip the build.                              |
| `.cursor/cloud/record.sh`            | agent, steps 2, 8, 10  | `start <name>` / `stop`: wraps `sim-remote simctl io <UDID> recordVideo` and downloads `media/<name>.mp4`.                                                      |
| `.cursor/cloud/stop.sh`              | agent, step 13         | Stops any recording, both reverse tunnels, `simctl shutdown`, `sim-remote logout`, `mock-backend.sh stop`.                                                      |
| `.cursor/cloud/pr-body.md`           | agent, step 12         | PR description template; thumbnails in a table, videos attached with `gh --attach`.                                                                             |

Why `metro.sh` calls the expo CLI entry directly: `npx expo` refuses to run when the Node major does not match `devEngines`, and pnpm's script wrapper has been seen to hang after its pre-run install. The argent MCP server is the stdio server registered in the MCP dropdown at cursor.com/agents (section 1.8; the repo's `.cursor/mcp.json` is not read by cloud agents); it spawns the tool-server on the VM the first time a tool is called, after `start.sh` has logged in, so `list-devices` sees the runner. The `ensure-sim-remote.sh` step has no guarantee of its own: it runs because `environment.json` calls `install.sh` at build time (warning only) and `start.sh` at every run (hard failure).

---

## 3. The agent runbook

Each step has a success check. The prompt should tell the agent to stop and report if a check fails twice.

### Step 1. Verify the environment

```bash
source .cursor/cloud/session.env         # SIM_UDID, METRO_PORT, PDS_PORT, MOCK_PDS_URL, MOCK_APPVIEW_DID, MOCK_USER
node -v && pnpm -v                        # v24.x, 11.21.x
gh auth status                            # authenticated via GH_TOKEN
gh --version                              # 2.99 or newer, needed for --attach
eas whoami                                # authenticated via EXPO_TOKEN
argent --version                          # 0.24.x, the global install the MCP server uses
bash .cursor/cloud/mock-backend.sh status # postgres, redis, manager :1986, PDS :3000 all ok
grep EXPO_PUBLIC_BLUESKY_PROXY_DID .env   # equals MOCK_APPVIEW_DID
sim-remote list-machines                  # one machine marked with *
sim-remote simctl list devices booted     # the simulator from start.sh
sim-remote reverse status                 # SIM_UDID with 8081 and 3000
curl -s http://localhost:8081/status      # packager-status:running
```

Then through argent MCP: `list-devices` must include `$SIM_UDID` with `platform: "ios-remote"`. If the argent tools are missing entirely, the server is not enabled in the MCP dropdown at cursor.com/agents for this account, or the agent was started before it was enabled (section 1.8). If the list is empty, the tool-server does not see the `sim-remote` session: run `sim-remote list-machines` from the terminal; if that shows a machine, the MCP process runs under a different user or `HOME` than `start.sh` did; if it does not, re-run `bash .cursor/cloud/start.sh`.

### Step 2. Smoke-test screenshots and recording before building

- argent `screenshot` on `$SIM_UDID` returns an image.
- Recording, the way steps 8 and 10 do it:
  ```bash
  bash .cursor/cloud/record.sh start smoke
  sleep 4
  bash .cursor/cloud/record.sh stop      # prints the duration of media/smoke.mp4
  ```
  If the file is missing or empty, stop and report; do not proceed to a 20-minute build without a video path that works.

### Step 3. Create the working branch and decide the change

```bash
git checkout -b agent/<short-change-name>
```

Pick a small, JS-only change that is visible within two taps of the Following feed (composer placeholder text, an icon color in the post controls, a header label). A native change would need another EAS build; this plan budgets one. Avoid features the mock appview lacks (post search, Explore suggestions, images).

### Step 4. Build the dev client on EAS and download it

Build first, before editing anything, so the native app matches the branch and the JS work happens while nothing else is waiting:

```bash
bash .cursor/cloud/get-dev-client.sh          # eas build (dev-sim) -> poll -> download; last line is the .app path
ls build/Debug-iphonesimulator                 # Bluesky.app, BlueskyClip.app
```

The script prints the build URL, then one status line per minute, then `version 1.132.0 build N` and the path. Expect 15 to 25 minutes on the medium class. `--reuse-latest` downloads the newest finished `dev-sim` build instead; use it only when the prompt allows it.

Failure modes to name in the prompt:

- `eas-cli is not authenticated`: the `EXPO_TOKEN` secret is missing or the agent was created before it was added.
- `Large resource classes are only available for subscribers`: wrong profile, use `dev-sim`.
- `No remote versions are configured`: counters not initialized (section 1.2).
- Owner/slug/projectId mismatch: `app.config.js` does not match the Expo project.
- `Code signature validation failed: No expo-signature header specified` when the app opens: built with `EXPO_PUBLIC_ENV=production`; rebuild with `development`.
- `unable to spawn process '/../../node_modules/react-native/scripts/xcode/ccache-clang.sh'` in an extension target: ccache enabled on EAS; keep the `EAS_BUILD` guard in `app.config.js`.

### Step 5. Install it on the cloud simulator

Install with argent `reinstall-app` (`udid: $SIM_UDID`, `bundleId: xyz.blueskyweb.app`, `appPath: build/Debug-iphonesimulator/Bluesky.app`); on an ios-remote device it uploads the bundle through sim-remote. Equivalent CLI: `sim-remote simctl install "$SIM_UDID" build/Debug-iphonesimulator/Bluesky.app`.

Success check: `sim-remote simctl listapps "$SIM_UDID" | grep xyz.blueskyweb.app`.

### Step 6. Open the dev client against Metro

The dev-client deep link scheme is `exp+<slug>`; with slug `social-app-demo` it is:

```
exp+social-app-demo://expo-development-client/?url=http%3A%2F%2Flocalhost%3A8081
```

`localhost:8081` is correct from the simulator's point of view because of the `reverse` tunnel. Use argent `open-url` (or `sim-remote simctl openurl`). Then:

1. iOS may ask "Open in Bluesky?" the first time: tap Open.
2. The dev client shows its developer-menu intro on a fresh install: tap Continue, then the X to close the dev menu.
3. `await-ui-element` visible `signInButton`, timeout 120 s, retried once (the first bundle of this app is large).
4. argent `debugger-status` on `$SIM_UDID` must say `connected`, port 8081. If it says `metro_not_running`, the Metro terminal died; if the app shows the launcher with a connection error, the reverse tunnel is down (`sim-remote reverse status`).

### Step 7. Log in to the mock network

Same path as `__e2e__/flows/login.yml`:

1. Tap `signInButton`.
2. Tap "Change hosting provider" (`selectServiceButton`), then the "Manual" tab (`manualSelectBtn`).
3. `paste` `http://localhost:3000` into `customServerTextInput` (paste, not type: the simulator's autocorrect turns a typed `localhost` into `local host`), then tap `doneBtn`. From the simulator, `localhost:3000` is the VM's mock PDS through the second tunnel.
4. `paste` `alice.test` into `loginUsernameInput`.
5. Tap `loginPasswordInput`, `keyboard` text `hunter2`, `keyboard` key `enter`. If `paste` reports no transport on the ios-remote device, fall back to `keyboard` for the URL and handle and verify the field values with `describe`.
6. Dismiss the fresh-install prompts: iOS notifications (Don't Allow), iOS Save Password (Not Now), the Age Assurance screen (Add your birthdate, keep the default, Save), and the "Please verify your email" sheet (Maybe later).
7. Success check: `await-ui-element` visible `bottomBarHomeBtn`, and the Following feed shows Bob's "Thread root", Carla's "Thread reply" and the seeded "Post" entries.

If login fails with a network error, `bash .cursor/cloud/mock-backend.sh status` and `sim-remote reverse status` tell which half is down. If the feed loads but every request after login fails, `.env` and the seeded DID drifted: run `bash .cursor/cloud/mock-backend.sh seed`, restart the `metro` terminal with `--clear` (`node_modules/expo/bin/cli start --dev-client --port 8081 --clear`), reopen the app.

### Step 8. Record "before"

1. Write the flow down first as a list of argent calls, or record it as an argent flow (`flow-start-recording` ... `flow-finish-recording`), because "after" must repeat it exactly. Keep it under 20 seconds: for example open the composer, wait 1 s, cancel, scroll the feed once. On the mock network the flow may also post, like or follow; nothing leaves the VM. Short flows also keep the MP4 under the 10 MB attachment limit.
2. `bash .cursor/cloud/record.sh start before`, run the flow with argent, `bash .cursor/cloud/record.sh stop`.
3. Take one argent `screenshot` of the changed area as a static thumbnail and save it as `media/before.png`.

### Step 9. Make the change and push it to the simulator

1. Edit under `src/`. Fast Refresh applies it through the reverse tunnel; if nothing changes within a few seconds, call `debugger-reload-metro`.
2. Verify with `describe` that the changed element shows the new text/label before recording.
3. Run the checks the PR expects:
   ```bash
   pnpm typecheck:ios && pnpm lint && node_modules/.bin/prettier --check <changed files>
   ```
   Never run `pnpm intl:extract` or `pnpm intl:compile`; CI owns them.

### Step 10. Record "after"

`bash .cursor/cloud/record.sh start after`, replay the same flow (execute the saved argent flow), `bash .cursor/cloud/record.sh stop`, plus `media/after.png`. If the flow mutates seeded data (a like, a post), reseed between the two recordings with `bash .cursor/cloud/mock-backend.sh seed` and restart Metro with `--clear` so both videos start from the same state.

### Step 11. Fit the media to GitHub's attachment limits

`gh --attach` accepts MP4 up to 10 MB on Free plans (100 MB on paid) and images up to 10 MB. Simulator recordings at native resolution can exceed that, so re-encode both videos to 720p and check the sizes:

```bash
for n in before after; do
  ffmpeg -y -i media/$n.mp4 -vf "scale=-2:720" -c:v libx264 -preset veryfast -crf 28 -pix_fmt yuv420p -movflags +faststart -an media/$n-720p.mp4
  ls -l media/$n-720p.mp4
done
```

If a file is still above the limit, raise `-crf` (30 to 34) or shorten the flow. GIF via `ffmpeg ... media/$n.gif` plus `gifsicle -O3` remains the fallback when a plan's video limit cannot be met; GIFs are attached the same way.

### Step 12. Commit and open the PR with the videos attached

```bash
git add src/ && git commit -m "<what changed, in the repo's style>"
git push -u origin agent/<short-change-name>
```

Copy `.cursor/cloud/pr-body.md` to `pr-body.md`, fill in the paragraph and `BUILD_ID`, and create the PR with the media attached:

```bash
gh pr create --base main --head agent/<short-change-name> --title "<title>" --body-file pr-body.md \
  --attach './media/before.png#Before' --attach './media/after.png#After' \
  --attach './media/before-720p.mp4#Before' --attach './media/after-720p.mp4#After'
```

How the body and the attachments combine:

- The template references `./media/before.png` and `./media/after.png` with image markdown inside the Before/After table; `gh` rewrites those local paths to the uploaded asset URLs, so the table shows the two thumbnails.
- The two MP4s are not referenced in the body on purpose. `gh` appends unreferenced attachments at the end of the description in the order given, each as a GitHub user-attachment, which is the form GitHub renders as an inline video player. The `#Before` / `#After` alt text labels them.
- Never attach the raw recordings; use the 720p files from step 11.

Success check:

```bash
gh pr view --json url,body | jq -r '.url, (.body | scan("https://github.com/user-attachments/assets/[^)\\s]+"))'
```

Expect the PR URL followed by four user-attachment URLs (two images, two videos). If fewer appear, an upload failed: check the size limits and rerun with `gh pr edit <number> --attach ...` for the missing files.

### Step 13. Clean up (mandatory: the runner is shared)

```bash
bash .cursor/cloud/stop.sh
```

Plus argent `stop-all-simulator-servers` with `devices: [$SIM_UDID]`. Report the PR URL, the EAS build id, and the attachment URLs.

---

## 4. Draft of the coordinating prompt

```
You are working in a Cursor Cloud VM on <owner>/<repo>, branch <base>. There is no simulator on this
machine. Argent Cloud provides one: .cursor/cloud/start.sh already ran `sim-remote login`, booted a
simulator (UDID in .cursor/cloud/session.env) and opened `sim-remote reverse start <UDID> 8081` and
`... 3000`, so the simulator reaches Metro (terminal "metro", port 8081) and the local mock Bluesky
network (PDS on port 3000) at its own localhost. The mock network is seeded with alice.test, bob.test
and carla.test (password hunter2, a public test fixture); nothing you do there is visible outside the VM.
Argent's MCP tools (server "argent", enabled in the MCP dropdown at cursor.com/agents) see that simulator as
platform "ios-remote"; use them for describe/tap/type/screenshot.
Paths you pass to argent or `sim-remote simctl install` are local paths; they are uploaded for you.
git pushes use Cursor's GitHub integration; `gh` is authenticated through GH_TOKEN.

Task: <describe the visible UI change, file, and expected result>.

Follow docs/cloud-agent-plan.md section 3 in order. Rules:
- Verify the environment (3.1) and smoke-test recording (3.2) before building. Stop and report if either fails twice.
- Build the app with `bash .cursor/cloud/get-dev-client.sh` (EAS profile dev-sim, then download). Never use the
  `development` profile. Use `--reuse-latest` only if this prompt says a fresh build is not required.
- Open the app with `exp+social-app-demo://expo-development-client/?url=http%3A%2F%2Flocalhost%3A8081`.
- Log in via hosting provider Manual -> http://localhost:3000 as alice.test / hunter2. Paste the URL and the
  handle, do not type them. Never change the hosting provider to bsky.social.
- Record before and after with .cursor/cloud/record.sh (argent recording does not support remote simulators)
  and the SAME argent flow: save the flow first, then replay it. If the flow changes data, reseed with
  `bash .cursor/cloud/mock-backend.sh seed` and restart Metro with --clear between the two recordings.
  Re-encode to 720p and keep each video under 10 MB.
- Only JS/TS changes. Run `pnpm typecheck:ios` and `pnpm lint`. Never run `pnpm intl:*`.
- Open the PR with `gh pr create --body-file pr-body.md` and `--attach` for the two PNG thumbnails and the two
  720p MP4s (alt text #Before / #After). Do not commit media, do not create branches or releases for it.
  Verify with `gh pr view --json body` that four user-attachments URLs are present.
- Never commit .env, google-services.json, ios/, build/, media/, or generated files under .cursor/cloud/.
- Always finish with `bash .cursor/cloud/stop.sh`, even on failure. Report the PR URL, the EAS build id, and
  the attachment URLs.
```

---

## 5. Risks and things to verify

| Risk                                                                                                    | Impact                                        | Mitigation                                                                                                                    |
| ------------------------------------------------------------------------------------------------------- | --------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| Mock network memory and CPU on Cursor's "limited" VM profile (Postgres + Redis + PDS + appview + Metro). | Slow or OOM-killed run                        | Verified in the amd64 image on a laptop; if the VM is too small, raise its profile or move the mock to `MOCK_SEED=users` only. |
| Seeded appview DID drifts from `.env` (reseed without a Metro restart).                                 | Every request after login fails               | `mock-backend.sh seed` prints the DID; restart the `metro` terminal with `--clear` afterwards; step 1 greps `.env`.            |
| EAS build per run: 15 to 25 minutes and one build of quota each time; queue waits on the free tier.     | Slow runs, quota exhaustion                   | `--reuse-latest` when the prompt allows; `BSKY_DEV_CLIENT_URL` as an escape hatch.                                            |
| argent not enabled in the MCP dropdown at cursor.com/agents (the repo's `.cursor/mcp.json` is ignored by cloud agents, confirmed), or the MCP process runs under a different user/HOME than `start.sh`. | No argent tools, or `list-devices` empty | Section 1.8; start a new agent after enabling; step 1 compares `list-devices` with `sim-remote list-machines` from the terminal. |
| Fleet fully leased; `login` waits for a free runner.                                                    | Run stalls at start                           | `start.sh` waits 300 s; report if it still fails.                                                                             |
| Session expires or the sim-remote daemon dies mid-run; tunnels die with it.                             | argent tools, Metro and PDS connections stop  | Re-run `start.sh`; `list-machines` + `attach` if the lease survived.                                                          |
| `recordVideo` stop/download semantics over sim-remote (SIGINT, `--force`).                              | No video files                                | Step 2 smoke test; `record.sh` polls for the download and prints the duration.                                                |
| argent `paste` on ios-remote may lack a transport.                                                      | URL or handle typed with autocorrect errors   | Fall back to `keyboard`, verify with `describe`, retry with backspaces.                                                       |
| Dev client built with `EXPO_PUBLIC_ENV=production` enforces update code signing.                        | Launcher error instead of the app             | `dev-sim` sets `EXPO_PUBLIC_ENV=development`.                                                                                 |
| ccache enabled on EAS breaks the extension targets.                                                     | Build fails                                   | `ccacheEnabled: IS_DEV && !process.env.EAS_BUILD` in `app.config.js`.                                                         |
| Wrong deep-link scheme after the slug change.                                                           | `openurl` fails with LaunchServices error 115 | Scheme is `exp+social-app-demo://`.                                                                                           |
| First bundle takes 1 to 3 minutes; iOS autocorrect edits typed text.                                    | False failures                                | Long `await-ui-element` timeouts; `paste` for URLs and handles.                                                               |
| `npx` refuses to run under a mismatched Node; pnpm script wrapper can hang.                             | Commands stall                                | Dockerfile pins Node 24; scripts call `node_modules/expo/bin/cli` and `node_modules/.bin/*`.                                  |
| Video over the attachment limit (10 MB Free, 100 MB paid) or `gh` older than 2.99.                      | Upload rejected, PR without videos            | Step 11 re-encodes to 720p and checks sizes; the image ships gh 2.100; GIF fallback attaches the same way.                     |
| `GH_TOKEN` scoped to the wrong repo, or the fork not writable by Cursor's app.                          | Push or PR creation fails                     | Step 1 runs `gh auth status`; use a fork the Cursor GitHub App can write to.                                                  |
| Runner left leased after a crash.                                                                       | Blocks the fleet                              | `stop.sh` is the last step of the prompt, also on failure; humans check `sim-remote list-machines`.                           |

---

## 6. Ports and paths cheat sheet

| What                | Where                                             | Reached as                                              | Notes                                                                 |
| ------------------- | ------------------------------------------------- | ------------------------------------------------------- | --------------------------------------------------------------------- |
| Metro               | VM, 127.0.0.1:8081                                | simulator: `localhost:8081` via `sim-remote reverse`    | dev client URL uses localhost                                         |
| Mock PDS            | VM, 127.0.0.1:3000                                | simulator: `localhost:3000` via `sim-remote reverse`    | hosting provider "Manual" in the sign-in form                         |
| Mock server manager | VM, 127.0.0.1:1986                                | VM only                                                 | `POST /?users&follows&posts&thread&feeds` reseeds and returns the DID |
| Postgres / Redis    | VM, 127.0.0.1:5433 (pg/password) / 127.0.0.1:6380 | VM only                                                 | started by `mock-backend.sh services`                                 |
| argent tool-server  | VM (auto-spawned by the MCP server)               | local                                                   | sees the runner's simulators as `ios-remote` after `start.sh`         |
| EAS artifact        | `build/Debug-iphonesimulator/Bluesky.app` on VM   | `reinstall-app --appPath` / `sim-remote simctl install` | uploaded to the runner automatically                                  |
| Recordings          | `media/*.mp4`, `media/*-720p.mp4` on the VM       | `.cursor/cloud/record.sh start\|stop`, then ffmpeg      | attached to the PR with `gh --attach`; never committed                |
| Simulator           | Argent Cloud runner                               | `$SIM_UDID` from `.cursor/cloud/session.env`            | booted in `start.sh`                                                  |

Sources: the sim-remote user guide, argent tool-server strings (`ios-remote` platform, `sim-remote` dependency, "remote simulators are unsupported" for recording), Cursor cloud agent docs (https://cursor.com/docs/cloud-agent, https://cursor.com/docs/cloud-agent/setup, https://cursor.com/docs/cloud-agent/builds, https://cursor.com/docs/cloud-agent/security-network), the GitHub changelog on media attachments in the CLI (https://github.blog/changelog/2026-09-01-github-cli-media-in-issues-pull-requests-and-comments/), and this repo's `docs/build.md`, `docs/testing.md`, `dev-env/`, `eas.json`, `app.config.js`, `__e2e__/flows/login.yml`.
