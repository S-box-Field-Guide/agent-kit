# Publishing to sbox.game

The org/ident/publish pipeline, store-page requirements, platform services,
Play Fund, and standalone Steam export. Researched 2026-07 from the Facepunch
sbox-docs repo, sbox.game news posts, the Facepunch EULA, and GitHub issues
 — items only discoverable in the in-editor
publish dialog are marked `(unverified)`; **record the answers here at first
publish**.

Platform context: s&box left early access and launched on Steam **2026-04-28**
($19.99). Front page has a spotlight section for new/under-appreciated games —
the discovery bar is currently low, the professionalism bar is the quality
metric below.

## Org, ident, and publish state

- **Create an Organization** via the in-editor publish dialog → "New
  Organisation" (opens sbox.game in browser), or directly on sbox.game. A
  freshly created org may not appear in the editor's Organisation dropdown
  until you **restart the editor**. The org name is the public prefix on every
  package the org ever ships — pick carefully.
- **Ident is `org.package`** — exactly two lowercase dot-separated segments.
  Whether package names may contain `_` is `(unverified — check the dialog)`.
  Title and ident are changeable per the getting-started docs, but ident
  mutability *after first publish* is `(unverified)` — treat first publish as
  permanent naming.
- **Publish from the editor**: Project menu → **"Publish Project…"** — one-click
  upload of game + assets (`Editor.ProjectPublisher.Publish`). Then finish on
  the web ("View and Edit on Web"): title, thumbnail, description, tags,
  categories, screenshots, video.
- **Default visibility is org-private.** Confirmed publish states: **Private,
  Unlisted, Released**. Nothing is public until you flip Publish State →
  Released. Unlisted + a direct link is the natural playtest channel.
- **Updates** = bump version and republish under the same ident. No enforced
  semver and **no platform changelog field** (keep your own CHANGELOG.md).
  Rollback behavior `(unverified)`.
- **Maps are separate packages** — a standalone map gets its own ident and
  earns Play Fund independently of the game.
- **No pre-publish review.** Publishing is instant; moderation is post-hoc
  (reports, review tags, EULA enforcement). No age-rating/mature-content
  toggle exists as of 2026-07.

## Store page: the quality metric

- **The discovery algorithm actively demotes packages missing any of:
  thumbnail, description, tags, categories, screenshots, or video.** A
  bare-minimum publish gets buried by design — treat every field as
  launch-blocking, not nice-to-have. Tags and categories are **distinct
  fields, both scored**.
- **AI-generated thumbnails are demoted** (policy since 2026-05-13):
  moderators flag them and demote ranking, with at least one reported
  false-positive on partially-AI art; the editor's thumbnail page carries a
  warning. Cover art must be unmistakably human-made.
- **Video/animated media on package pages: mp4, webm, gif, animated webp** —
  native file playback from disk or URL. YouTube embedding
  `(unverified/unlikely)`.
- **Thumbnail and banner pixel dimensions are documented nowhere** (official
  docs, wiki, community guides all silent). Pre-redesign wiki said 1280×720
  for the banner `(unverified for the current site)`. Read the upload form's
  own validation text when publishing and record it here.
- Description character limit, title limit, and screenshot count limit: all
  `(unverified — check the dialog)`.

## Sandbox.Services (stats, leaderboards, achievements)

The default pause menu surfaces achievements, leaderboards, stats, reviews,
and forums per game (platform update 26.01.07 — verify current behavior).
Wiring these is cheap and makes a game look finished on the platform.

- **Stats** — `Stats.Increment("ident", 1)` / `Stats.SetValue("ident", v)`.
  Batched automatically; global, local, and per-player reads.
- **Leaderboards** — built on demand from any stat
  (`Leaderboards.GetFromStat`); aggregation sum/min/max/avg/last;
  daily/weekly/monthly/yearly buckets + country filters; `.CenterOnMe`.
  Free public web API:
  `https://public.facepunch.com/sbox/package/{ident}/leaderboard/{stat}/`.
- **Achievements** — score 5–100 each, **game total capped at 1000**. Icons
  are auto-resized to **128×128** (the one confirmed pixel dimension on the
  whole platform). Two unlock mechanisms: stat-threshold auto-unlock (gets a
  progress bar for free) or manual `Achievements.Unlock("ident")`.
- **Auth tokens** exist for validating players against a custom backend.
- The legacy `.sbproj` fields `LeaderboardType`/`RankType` may be vestigial
  now that Sandbox.Services exists `(unverified)`.

## Play Fund (monetization)

- There is **no paid-games storefront**; on-platform revenue is the Play Fund —
  a daily pool (~$1M/yr after the Steam launch) split across games/maps by
  **clamped individual player-hours** (secret algorithm; clamping means
  botting/idling doesn't pay).
- **$100 minimum balance**, paid monthly mid-month; payment details in profile
  settings; revenue **splittable across team members** (org membership not
  required for a split).
- **Eligibility:** no copyrighted material; no "repackaging someone else's
  work with no real creativity." sbox.game cloud assets are implicitly
  licensed and fine. The Publish Wizard shows a per-cloud-asset
  eligibility/license check — heed it.
- Payouts are **discretionary per the EULA** ("Creators do not have any right
  to compensation") — treat the Play Fund as upside, not a business plan.
- Practical implication: revenue tracks session hours, so retention features
  are literally the monetization features.

## Standalone Steam export (status as of 2026-07)

- Since the March 2026 Facepunch–Valve license, s&box games can export as
  standalone Steam titles **royalty-free** (only Steam's cut). Currently **in
  preview**: distribution requires **Valve approval per title** plus a license
  from Facepunch ("email garry@facepunch.com"); pilot cohort only — nothing
  has actually shipped standalone yet.
- Mechanics: Project menu → **Export…** → icon, splash screen, Steam App ID →
  self-contained executable. Base export ~500MB. PC only; the game **must be
  on Steam** (other stores allowed additionally).
- Trade-offs: standalone gets full .NET (no whitelist) + engine source access,
  but **loses all platform services** — cloud asset streaming, backend
  leaderboards/stats/achievements, and the sbox.game social layer.
- **A standalone build that still has PackageReferences can hang on startup**
  (it can't reach sbox.game to resolve them) — keep the dependency list clean
  before exporting.

## Hard gotchas

- **Whitelist divergence post-publish** — game code runs under an API
  accesslist (no `Process.Start`, `DllImport`, raw `System.IO`, reflection),
  and a package that compiles clean in-editor **can still fail whitelist
  checks for players after publish**, especially across engine updates
  (Facepunch/sbox-public #11228, June 2026, unresolved). Fix: after every
  publish AND every s&box engine update, join the published package **as a
  player, not in-editor**, before announcing anything.
- **Loose resource files don't auto-publish.** Non-compiled assets (PNG, WAV,
  MP3, JSON…) must be listed in Project Settings → Other → **Resource Files**,
  and the paths must **not** be prefixed with `assets/`. The #1 cited cause of
  "worked in editor, broken after publish."
- **Cloud assets fail silently under backend load** — a published game boots
  with `error.vmdl` placeholders and the engine even rewrites prefab refs to
  error.vmdl. No auto-retry exists; workaround is an editor restart +
  republish. Minimize cloud-asset use, or pin and verify each one after
  publish.
- **Disabling the whitelist blocks platform publish entirely** — it's a
  one-way door to standalone-only. Never flip it casually.
- **Min specs to test against:** Vulkan 1.2 required, no DX11 fallback, Intel
  iGPU unsupported; official floor i5-7500 / 8GB / GTX 1050. Steam Deck is
  effectively unsupported (unrated, poor perf, no default controller scheme).
- **Upload size cap: none documented** — watch total package size at first
  publish and record the number here.

## Multiplayer at publish

- Discovery is via **Steam lobbies inside the game's own UI** — there is no
  global server browser. Host-tags-lobby-metadata + joiner-searches-lobby-list
  is the supported pattern.
- Check `Sandbox.Network.LobbyConfig.Privacy` defaults before release so
  random players can't hot-join (or can, if you want public lobbies).
- Dedicated servers: launch with `+game <org.package>` and set
  `+net_game_server_token` — **without the token the server gets a new Steam
  ID on each restart, breaking reconnects**.

## Open items to verify at first publish (nowhere else documented)

Record answers in this file when a project first publishes:

- Thumbnail + banner exact pixel dimensions / aspect ratio / format
- Description & title character limits; screenshot count limit
- Full Publish State enum (anything beyond Private/Unlisted/Released?)
- Whether idents may contain `_`, and whether ident is mutable post-publish
- Package upload size limit
- Whether `LeaderboardType`/`RankType` in .sbproj still do anything
