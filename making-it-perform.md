# Making it perform — skill pack

> Lane pack. Load `_core.md` first, then this file. Denser than the articles by design;
> when a bullet matches, open the matching `content/articles/<slug>.md`. Sanitized public
> advice; unconfirmed details marked `(needs verification)`. The sync appends new bullets here.


- **Editor-embedded play mode is hard-capped at the desktop's vsync (60 Hz) and it is NOT
 liftable via any cvar.** `r_frame_sync_enable 0` AND `fps_max 0` were both confirmed set
 (read the value back — it echoes "0") and fps still pinned at EXACTLY 60.0 (300 frames / 5 s
 window). The cap is the compositor's vsync on the editor window's present, not the engine
 frame-sync. Consequence for any perf study driven through the editor MCP loop: you CANNOT
 measure the true GPU ceiling — `avg = 60.0` only means "the engine met every 60 Hz deadline".
 The real knee is `avg < 60` WITH a collapsing p1 (1% low). one project held a locked 60 fps
 up to 2.03 M render tris / 2304 draw calls / 900+ static ModelColliders — render never bound.
- **For a chunked runtime-mesh generator, REGEN (single-threaded generation CPU) is the binding
 resource, not fps or draw calls — and regen is generation-math-bound, not scene-object-bound.**
 the project's regen grows ~linearly with cell count (WorldSize²): 384²≈0.4 s → 1024²=2.3 s →
 1280²=3.6 s → 1536²=5.4 s (the wall — busts a 5 s budget). Decisive evidence it's the passes not
 CreateObject/collider build: bumping ChunkCells 32→64 QUARTERED the GameObject/ModelCollider
 count (1024→256 chunks) at 1024² with ZERO regen change (2286 vs 2257 ms). So the lever to push
 density further is THREADING the pure passes (GameTask.RunInThreadAsync), never bigger chunks.
 Corollary: don't raise ChunkCells for a draw-call reason — draw calls never bound fps here, and
 smaller chunks keep finer dirty-remesh granularity for a brush editor.
- **Voxel GRAIN (CellSize) is nearly free; the density knob the art wants costs almost nothing.**
 At a fixed WorldSize, CellSize 0.5→0.4→0.3 m barely moved tris or regen (512² all ~315 k tris,
 ~580 ms) — CellSize only changes the physical footprint, not the cell COUNT that drives cost.
 StepHeight 0.25→0.125 m costs +~54% tris and drops greedy efficiency (finer steps split
 same-height runs: 2.1→1.6×) but fps/regen stay flat. So "smaller blocks" = raise WorldSize AND
 shrink CellSize proportionally to hold the footprint: finer grain at constant perf AND constant
 scatter density (scatter is a fixed INSTANCE budget, so a constant footprint preserves density;
 a bigger footprint dilutes it).
- **fps-probe measurement hygiene through the MCP loop:** `read_console` accumulates lines across
 play sessions, so (1) delimit "this session's" fps lines by the fresh `[boot] boot:` marker that
 each play_start logs, (2) DROP the last window (it carries the play_stop hitch — shows a false
 p1 like 0.5/29), and (3) sample ≥3 clean windows (≥18 s play): a 1-window sample routinely
 catches a stray hitch and reports a bogus avg=48/p1=28 for a rung that actually holds a rock-solid
 60. Skip a warmup (~1.5 s) in the probe so the play-start world-build hitch never poisons window 1
 — but if the build itself exceeds the warmup (>1.5 s regen), it still bleeds into window 1.
 Also: a game-assembly static (WorldGen.CurrentSpec) SURVIVES the editor→play boundary (same
 process, no assembly reload), so you can benchmark an editor-generated spec in play mode by
 having Bootstrap read that static.