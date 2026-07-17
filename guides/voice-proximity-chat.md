---
title: "Proximity voice chat — the built-in Sandbox.Voice component"
slug: voice-proximity-chat
date: "2026-07-14T20:30:00-04:00"
updated: "2026-07-15T00:24:00-04:00"
lanes:
  - writing-gameplay
  - audio
tags:
  - voice
  - networking
  - audio
  - multiplayer
  - proximity
summary: >-
  The complete method for wiring s&box's built-in Voice component into a
  networked game — push-to-talk, 3D positional playback, custom falloff curves,
  speaking indicators, and lip-sync — with no third-party voice SDK.
sourceRev: e1f75bb3a8cd
relatedFixes:
  - custom-sound-wont-play
  - authoring-sound-events-by-hand
  - soundevent-no-looping-field
  - playing-sound-static-api
unverified: false
---

s&box ships a complete, networked microphone/voice system — you do **not** need to hand-roll Steam voice capture, Opus transmission, or 3D playback. It is one engine component: `Sandbox.Voice`.

## 1. The component surface

`Voice` (`public class Voice : Component`) records and transmits voice/microphone input to other players. Attach one per player object. The full API surface:

| Member | Meaning |
|---|---|
| `enum ActivateMode { AlwaysOn, PushToTalk, Manual }` | How the mic keys on. |
| `ActivateMode Mode` | Default **AlwaysOn** — you almost always want `PushToTalk`. |
| `string PushToTalkInput` | InputAction name; default `"voice"`. Held while `Mode == PushToTalk`. |
| `bool WorldspacePlayback` | Default **true** — 3D positional playback at the component's `WorldPosition`, with occlusion. `false` = 2D `ListenLocal`. |
| `bool Loopback` | Default `false` = don't play the sound of your own voice. |
| `float Volume` | Default 1. |
| `float Distance` | Default **15,000 units (about 381 m)** — max attenuation distance. |
| `Curve Falloff` | Normalized distance `0..1` (where 1 = `Distance`) mapped to gain. The default curve is heavily front-loaded — wrong for a tight proximity bubble. |
| `bool LipSync` / `SkinnedModelRenderer Renderer` / `MorphScale` / `MorphSmoothTime` | Drives citizen viseme morphs from the live voice analysis. Safely no-ops if `Renderer` is invalid. |
| `RealTimeSince LastPlayed` | Resets to 0 on every received voice packet — the cleanest "is this player speaking" signal on a proxy. |
| `bool IsRecording` / `bool IsListening` | Local capture state. `IsListening` is the preference-gated truth. |
| `float Amplitude` | Live loudness of the playback sound. |
| `MixerHandle VoiceMixer` | Target mixer; must descend from `Mixer.Voice`. A user "voice volume" slider hooks here. |
| `float LaughterScore` / `IReadOnlyList<float> Visemes` | Analysis outputs. |
| `virtual IEnumerable<Connection> ExcludeFilter()` | Override to per-player MUTE (exclude connections from hearing you). |
| `virtual bool ShouldHearVoice(Connection)` | Override to per-player DEAFEN (drop a speaker). |

**Networking is built in.** The component transmits via `[Rpc.Broadcast(NetFlags.OwnerOnly | NetFlags.UnreliableNoDelay)]` — the owner records (Steam voice, 44.1 kHz, ~30 Hz read tick), compresses, and broadcasts; receiving peers decompress and play through a `SoundStream`. `IsListening` returns `false` when `IsProxy`, so a peer only ever transmits its own character. `Application.IsHeadless` short-circuits playback — a dedicated server is silent; voice relays peer-to-peer via the broadcast. A static `singleRecorder` ensures only one Voice records per client.

## 2. The wiring recipe

Two rules carry the whole feature:

**Rule A — attach to the networked player object BEFORE `NetworkSpawn`.** The component rides the replicated snapshot to every peer (the component-ordering law: create components, then `NetworkSpawn`). Attach only in the networked path — a solo character gets no Voice, giving zero mic activity in single-player with no null-guards needed:

```csharp
var go  = Scene.CreateObject();
var chr = go.Components.Create<MyCharacter>();
if ( owner is not null )
{
    go.Components.Create<Voice>();     // BEFORE NetworkSpawn
    go.NetworkSpawn( owner );
}
```

**Rule B — configure on every peer, not via replication.** Playback config on a proxy comes from that peer's own `OnStart`, not the snapshot. Set `Mode`, `Distance`, `Falloff`, and `PushToTalkInput` on every peer:

```csharp
protected override void OnStart()
{
    var voice = Components.Get<Voice>();
    if ( !voice.IsValid() ) return;   // solo mode — no Voice attached

    voice.Mode           = Voice.ActivateMode.PushToTalk;
    voice.PushToTalkInput = "Voice";
    voice.WorldspacePlayback = true;
    voice.LipSync        = true;
    voice.Distance       = VoiceMaxRangeM * 39.37f;   // metres → s&box units

    float nearRatio = VoiceNearRangeM / VoiceMaxRangeM;
    voice.Falloff = new Curve(
        new Curve.Frame( 0f,        1f, 0f, 0f ),
        new Curve.Frame( nearRatio, 1f, 0f, 0f ),
        new Curve.Frame( 1f,        0f, 0f, 0f ) );

    voice.Renderer = Components.Get<SkinnedModelRenderer>();
}
```

`Curve(params Frame[])` and `Curve.Frame(time, value, inTangent, outTangent)` are public. **Do not ship the default `Falloff` + `Distance`** for proximity chat — 381 m of range with the stock curve gives a mushy, map-spanning whisper instead of a crisp local bubble.

## 3. Push-to-talk: three layers

1. **The engine user preference is already PTT by default.** `Preferences.VoiceMode` (ConVar `voip_mode`, saved) defaults to `PushToTalk`. The `IsListening` logic: `Disabled` never transmits; `PushToTalk` always requires `Input.Down(PushToTalkInput)` regardless of component Mode; `OpenMicrophone` honors the component Mode.
2. **Bind the built-in `"Voice"` input action.** Every project's `ProjectSettings/Input.config` typically ships a `"Voice"` action (often with `KeyboardCode: None`); the component's default `PushToTalkInput = "voice"` binds to it — assign a free key and you're done. **Verify it exists** — not every project has it. If missing, add it to `Input.config` (editor restart required for input config changes to register).
3. **Set component `Mode = PushToTalk` anyway** (belt-and-suspenders): keeps PTT gating even for a user whose saved `voip_mode` is `OpenMicrophone` — without it, that user would hot-mic your game.

## 4. The speaking-indicator pattern

On a proxy, `voice.LastPlayed < holdSeconds` is a flicker-free "speaking" flag: packets arrive ~30/s while the mic is active, so a **~0.3 s hold window** bridges inter-packet gaps and clears shortly after the talker stops:

```csharp
var voice = chr.Components.Get<Voice>();
bool speaking = voice.IsValid() && voice.LastPlayed < 0.3f;
```

**Anchor the tag off the networked transform, not an owner-only sim field.** A proxy (the only character you tag) never runs the owner's `OnFixedUpdate`, so any private position field written there (and not `[Sync]`) freezes at the proxy's spawn value while the replicated `GameObject.WorldPosition` carries the real player. Anchor the tag off a frozen field and it strands at spawn while the model walks away. Read the character's `WorldPosition` (the same interpolated source the parented visual renders from) — it also satisfies the read-interpolated-transforms rule. In a live two-peer session, a tag anchored to an unsynced owner field was observed hanging over the spawn area while the player model stood elsewhere; switching to `WorldPosition` fixed it immediately.

For a Razor name-tag overlay, fold the flag into `BuildHash` so the DOM rebuilds only on a state change, not per frame. `Components.Get<Voice>()` returns null on a non-networked character, so `speaking = false` gives the correct solo behavior for free.

## 5. Falloff radii as tuning constants

House the radii as named constants in metres with doc comments; convert once at emission (s&box units are inches; 1 m = 39.37 units):

```csharp
public const float VoiceNearRangeM    = 8f;    // full-volume conversational core
public const float VoiceMaxRangeM     = 35f;   // silent at/beyond
public const float VoiceSpeakingHoldS = 0.3f;  // indicator hold window
```

These are live-tuning dials: the "how far can I hear them" feel can only be judged in a real two-peer session. Scale to your world footprint; the engine default (381 m) is effectively "everywhere" on a small map.

## 6. Extension points

- **Per-player mute:** subclass (`class MyVoice : Voice`) overriding `ExcludeFilter()` to yield the connections that should not hear you (applied via `Rpc.FilterExclude` around the broadcast).
- **Per-player deafen:** override `ShouldHearVoice(Connection)` to return `false` for speakers the local user muted.
- **Lip-sync:** set `Renderer` to the peer's `SkinnedModelRenderer` — the engine drives citizen viseme morphs from the live analysis, holds the shape through packet gaps, and eases out after ~1 s. If the model lacks viseme morphs, `LipSync` safely no-ops.
- **Team voice / screen-space stereo:** `WorldspacePlayback = false` puts the sound in screen space for team-left/right audio.
- **Occlusion:** enabled by default in worldspace playback. Only avoidable via a subclass override if terrain-muffled voice is wrong for your game.
- **Mixer routing:** `VoiceMixer` targets any descendant of the `Voice` mixer — the hook for a user voice-volume slider (don't repurpose `Volume` for that).

## 7. The two-peer verification checklist

Run once per project after wiring. Each row should be proven live:

| # | Check |
|---|---|
| 1 | Host + joiner in session, both possessed, name tags visible both ways |
| 2 | Hold PTT → other peer hears audio; speaking indicator lights; release → audio stops, indicator clears within the hold window. Both directions. |
| 3 | No self-hearing while transmitting |
| 4 | Falloff: walk away — clearly audible inside the near core, fading, silent by max range |
| 5 | Directionality: circle the speaker → voice pans; walk behind terrain → occlusion muffling |
| 6 | Lip-sync: speaker's citizen mouth visibly moves while talking |
| 7 | Solo sanity: single-player session has zero mic activity, zero errors |

Check #2 is the keystone — it proves the create-before-NetworkSpawn premise (that a proxy's `Msg_Voice` RPC arrives and plays). Everything upstream of #2 is compile-proven only.

## 8. Pitfalls

| ID | Pitfall |
|---|---|
| P1 | Component default `Mode` is **AlwaysOn** — a bare `Voice` relies entirely on the user's `voip_mode` preference. Always set `PushToTalk` explicitly. |
| P2 | Default `Distance` (381 m) and the default `Falloff` are wrong for proximity chat. Set both, with a tangent-0 plateau curve. |
| P3 | Playback config on a proxy comes from that peer's own `OnStart`, not replication — configure on every peer. |
| P4 | The `"Voice"` input action is usually but **not always** present in `Input.config`. Always verify; if missing, add it (editor restart required). |
| P5 | Dedicated server: `Application.IsHeadless` mutes playback — no server-side audio work needed. |
| P6 | Solo sessions: attach Voice only in the networked spawn path. This guarantees zero mic activity in single-player and makes `Get<Voice>() == null` the solo gate. |
| P7 | A sibling-component pattern works when the character class is frozen: create a new component alongside Voice on the same GameObject and configure the sibling in `OnStart`. No character edits needed. |
| P8 | If the `SkinnedModelRenderer` lives on a child GameObject, use `Components.Get<SkinnedModelRenderer>(FindMode.EnabledInSelfAndDescendants)` with a one-tick lazy retry (component start ordering isn't guaranteed). |
