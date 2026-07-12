# Audio — skill pack

> Lane pack. Load `_core.md` first, then this file. Denser than the articles by design;
> when a bullet matches, open the matching `content/articles/<slug>.md`. Sanitized public
> advice; unconfirmed details marked `(needs verification)`. The sync appends new bullets here.

## Audio (SFX / .sound events)

- **MP3 is a valid SOURCE audio asset — no wav conversion, no ffmpeg needed.** The engine's
  own `addons/menu/Assets/sounds/box_open.mp3` sits next to `box_open.sound` and compiles to
  `box_open.vsnd_c`. There is NO `.vsnd` source file (only the compiled `.vsnd_c`); the
  `.sound` event references the audio as `"sounds/<name>.vsnd"` and the engine maps the mp3 to
  it. Chain: `<name>.mp3` + `<name>.sound` → `<name>.vsnd_c` + `<name>.sound_c`.
- **The `.sound` event file is plain JSON you can AUTHOR AS TEXT** (schema = copy
  `addons/menu/Assets/sounds/box_open.sound`): `UI` (true=2D/false=3D positional), `Volume`/
  `Pitch` (strings), `Decibels`, `SelectionMode`, `Sounds` (vsnd refs), the Occlusion/Reverb/
  AirAbsorption/Transmission bools, `Distance` (max range in UNITS — ~1575u≈40 m positional,
  15000 for UI), a `Falloff` bezier curve, `DefaultMixer`, `__version`.
- **SoundEvent has NO `Looping` field** (verified vs `Sandbox.Engine.xml` — the loop `.sound`
  in the install is byte-identical to non-loop ones). Looping lives on the compiled `.vsnd`
  (`SoundFile.LoadOptions.Loop`), an editor-import concern. To loop from code with zero editor
  step: play, keep the `SoundHandle`, re-trigger when `.Finished`/`!IsPlaying`.
- **Playing sound is fully static:** `Sound.Play(eventString)` (2D) / `Sound.Play(eventString,
  worldPos)` (3D→`SoundHandle`). `SoundHandle`: `.Volume .Pitch .Position .IsPlaying .Finished
  .Stop(fadeSeconds) .IsValid`. A missing event doesn't hard-throw but wrap in try/catch so a
  not-yet-generated `.sound` can't break gameplay. No component/Bootstrap wiring needed (unlike
  stateful SharedState/RunStats).
- **The event STRING must be the FULL resource path WITH extension (`"sounds/impact/boing_a.sound"`)
  or the BARE filename (`"boing_a"`) — a partial path like `"impact/boing_a"` NEVER resolves**
. Decompiled contract (`Sandbox.Engine.dll` → `SoundEvent.Find`):
  (1) `ResourceLibrary.Get<SoundEvent>(name)` — a cache-HASH lookup keyed by the full
  `ResourcePath` incl. `.sound`; `Resource.FixPath` only normalizes slashes/strips `_c`, it never
  prepends `sounds/` or appends the extension, so partial paths can't hash-match; (2) fallback
  compares `ResourceName` — the bare FILENAME, which never contains `/`. The install's own
  `Sound.Play("cardboard_rustle_loop")` works only via form 2 — generalizing it to
  `"family/name"` (as the audio-v1 agent did) fits NEITHER form. Don't trust "Couldn't find
  sound event" to mean a missing/uncompiled asset: probe the LIVE editor first —
  it distinguishes name-form bugs from index/compile bugs in one call, no play mode needed.
  Fix pattern: translate house names at ONE boundary.

- **ElevenLabs SFX cost is the `character-cost` RESPONSE HEADER (~10 credits/sec), NOT the
  subscription counter** (`/v1/user/subscription` `character_count` lags at 0 on free tier —
  sum the header for live budgeting). `POST /v1/sound-generation` `{text,duration_seconds,
  prompt_influence}` → `audio/mpeg` (magic `ID3`). Bump `prompt_influence` to 0.5–0.6 for
  onomatopoeia (boing/bonk/slide-whistle), 0.25–0.35 for ambient loops.
- **ElevenLabs VOICES (NPC dialogue) use TTS, a SEPARATE endpoint from SFX**: `POST
  /v1/text-to-speech/{voice_id}?output_format=mp3_44100_128` with `{text, model_id:
  "eleven_multilingual_v2", voice_settings:{stability, similarity_boost, style, use_speaker_boost}}`
  → the same `ID3` mp3 the s&box pipeline ingests directly (identical .sound authoring afterward).
  Pick stock voice ids via `GET /v1/voices` (probe once; each has labels gender/age/descriptive/
  use_case — e.g. "characters_animation" for a theatrical guard). TTS bills ~1 credit/CHARACTER of
  text (not per second), so short barks are cheap; the `character-cost` header is still authoritative.
  Lower `stability` + higher `style` = more expressive/theatrical delivery. A gruff guard + 2 varied
  visitor voices + a chirpy vendor across 16 lines cost ~370 credits.
- **Ambient emitters** (kiosk jingles, per-pen animal calls, drifting crowd chatter): a small
  `Component` (AmbientEmitter) that either LOOPS a bed (Sfx.StartLoop under a unique per-object key
  + pumps Sfx.Tick from its own OnUpdate) or fires seed-jittered ONE-SHOTS rotating a name list
  (Sfx.PlayVaried). A static `SpawnAll(Scene)` places them all from ONE Bootstrap line AFTER the
  world build (coords mirror the builder's stand/zone centres). Positional-texture voices (phone/
  walla murmurs) get a LOW authored Volume (0.5) + SHORT Distance (~900u) in their .sound so they
  read as ambience, not blaring dialogue.
- **Per-speaker line cooldown**: gate every NPC voice bark through a `Time.Now - _lastLineAt <
  8f` check + a monotonic `_lineCount` fed into Sfx.PlayVaried's seed, so a spotted→pursue→lost
  flurry (guard) or surprise→delight→phone flurry (visitor) never machine-guns dialogue and two
  speakers don't sound identical. No RNG — deterministic pitch wobble.
