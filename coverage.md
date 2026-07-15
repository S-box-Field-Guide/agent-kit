# Gotcha coverage

> **Generated from the coverage registry.** Do not hand-edit. This is the human view of
> the authoritative skip-list: each source gotcha's `status` (`none` = backlog, `pack` =
> in the skill pack only, `article` = has a full Field Guide article). The sync never
> re-drafts an `article` gotcha, so duplicates can't happen by construction.

**140 / 512 gotchas articled** (27%). Pack-only: **156**. Backlog (status `none`): **216**.

## By lane

| Lane | Gotchas | Articled | Pack-only | Backlog | Coverage |
|---|--:|--:|--:|--:|--:|
| getting-art-in | 67 | 29 | 19 | 19 | 43% |
| rigging-animation | 29 | 20 | 3 | 6 | 69% |
| writing-gameplay | 244 | 41 | 84 | 119 | 17% |
| building-ui | 44 | 18 | 12 | 14 | 41% |
| audio | 11 | 5 | 5 | 1 | 45% |
| making-it-perform | 7 | 1 | 3 | 3 | 14% |
| tooling-environment | 110 | 26 | 30 | 54 | 24% |
| **Total** | **512** | **140** | **156** | **216** | **27%** |

## Articled gotchas (skip-list)

| Gotcha id | Article |
|---|---|
| `g-art-animated-sub-parts-need-their-origin` | [/fix/blender-headless-pipeline](https://sboxguide.dev/fix/blender-headless-pipeline) |
| `g-art-asset-paths-project-root-relative-forward` | [/fix/ai-generated-models](https://sboxguide.dev/fix/ai-generated-models) |
| `g-art-baked-scale-vmdl-wrapper-s-import` | [/fix/ai-generated-models](https://sboxguide.dev/fix/ai-generated-models) |
| `g-art-blender-rotation-sign-check` | [/fix/model-imported-wrong-facing](https://sboxguide.dev/fix/model-imported-wrong-facing) |
| `g-art-blender-s-obj-exporter-export-materials` | [/fix/decimating-ai-meshes](https://sboxguide.dev/fix/decimating-ai-meshes) |
| `g-art-bpy-ops-wm-obj` | [/fix/obj-export-face-order-nondeterministic](https://sboxguide.dev/fix/obj-export-face-order-nondeterministic) |
| `g-art-capsulecollider-radius-start-end-follow-worl` | [/fix/scaled-collider-didnt-scale](https://sboxguide.dev/fix/scaled-collider-didnt-scale) |
| `g-art-colliders-live-model-s-own-frame` | [/fix/model-imported-wrong-facing](https://sboxguide.dev/fix/model-imported-wrong-facing) |
| `g-art-default-scene-gravity-2-2g` | [/fix/sbox-units-are-inches](https://sboxguide.dev/fix/sbox-units-are-inches) |
| `g-art-disable-instance-shadows-renderer` | [/fix/disable-instance-shadows](https://sboxguide.dev/fix/disable-instance-shadows) |
| `g-art-double-tint-flat-color-vmat-override` | [/fix/model-tint-flat-vmat-traps](https://sboxguide.dev/fix/model-tint-flat-vmat-traps) |
| `g-art-flat-color-materials-constant-color-texturec` | [/fix/kenney-cc0-import](https://sboxguide.dev/fix/kenney-cc0-import) |
| `g-art-high-key-chalky-bright-near-white` | [/fix/high-key-chalky-sky-needs-texture-and-tonemapping](https://sboxguide.dev/fix/high-key-chalky-sky-needs-texture-and-tonemapping) |
| `g-art-instance-modelrenderer-tint-flat` | [/fix/model-tint-flat-vmat-traps](https://sboxguide.dev/fix/model-tint-flat-vmat-traps) |
| `g-art-meters-authored-waypoint-position-arrays-aud` | [/fix/sbox-units-are-inches](https://sboxguide.dev/fix/sbox-units-are-inches) |
| `g-art-meters-units-mixups-travel-packs-sweep` | [/fix/sbox-units-are-inches](https://sboxguide.dev/fix/sbox-units-are-inches) |
| `g-art-model-facing-geometry-built` | [/fix/model-imported-wrong-facing](https://sboxguide.dev/fix/model-imported-wrong-facing) |
| `g-art-modelcollider-s-physics-hull-also-follow` | [/fix/capsule-vs-box-collider-choice](https://sboxguide.dev/fix/capsule-vs-box-collider-choice) |
| `g-art-obj-importer-auto-converts-y-up` | [/fix/blender-headless-pipeline](https://sboxguide.dev/fix/blender-headless-pipeline) |
| `g-art-prefer-hand-sized-boxcollider-s-over` | [/fix/capsule-vs-box-collider-choice](https://sboxguide.dev/fix/capsule-vs-box-collider-choice) |
| `g-art-recovery-forge-delivery-fails` | [/fix/forge-failed-delivery-glb-recovery](https://sboxguide.dev/fix/forge-failed-delivery-glb-recovery) |
| `g-art-s-box-load-raw-obj-glb` | [/fix/sbox-wont-load-obj-glb](https://sboxguide.dev/fix/sbox-wont-load-obj-glb) |
| `g-art-s-box-units-inches` | [/fix/sbox-units-are-inches](https://sboxguide.dev/fix/sbox-units-are-inches) |
| `g-art-scene-triangle-overload` | [/fix/decimating-ai-meshes](https://sboxguide.dev/fix/decimating-ai-meshes) |
| `g-art-shaders-complex-shader-compiled` | [/fix/shader-template-field-discovery](https://sboxguide.dev/fix/shader-template-field-discovery) |
| `g-art-trajectory-aim-previews-sample-arc-length` | [/fix/trajectory-preview-arc-length-sampling](https://sboxguide.dev/fix/trajectory-preview-arc-length-sampling) |
| `g-art-vector3-right-0-1-0-x` | [/fix/vector3-right-is-negative-y](https://sboxguide.dev/fix/vector3-right-is-negative-y) |
| `g-art-vmdl-material-remaps-map-both-names` | [/fix/sbox-wont-load-obj-glb](https://sboxguide.dev/fix/sbox-wont-load-obj-glb) |
| `g-art-vmdl-rendermeshfile-compiles-clean-has-zero` | [/fix/model-no-collision](https://sboxguide.dev/fix/model-no-collision) |
| `g-audio-event-string-full-resource-path-extension` | [/fix/custom-sound-wont-play](https://sboxguide.dev/fix/custom-sound-wont-play) |
| `g-audio-mp3-valid-source-audio-asset-wav` | [/fix/authoring-sound-events-by-hand](https://sboxguide.dev/fix/authoring-sound-events-by-hand) |
| `g-audio-playing-sound-fully-static` | [/fix/playing-sound-static-api](https://sboxguide.dev/fix/playing-sound-static-api) |
| `g-audio-sound-event-file-plain-json-author` | [/fix/authoring-sound-events-by-hand](https://sboxguide.dev/fix/authoring-sound-events-by-hand) |
| `g-audio-soundevent-has-looping-field` | [/fix/soundevent-no-looping-field](https://sboxguide.dev/fix/soundevent-no-looping-field) |
| `g-game-cell-white-noise-hash-wrong-driver` | [/fix/white-noise-hash-terrain-shade](https://sboxguide.dev/fix/white-noise-hash-terrain-shade) |
| `g-game-component-active-real-inherited-member` | [/fix/component-active-naming-shadow](https://sboxguide.dev/fix/component-active-naming-shadow) |
| `g-game-custom-components-scene-json` | [/fix/four-object-scene-bootstrap](https://sboxguide.dev/fix/four-object-scene-bootstrap) |
| `g-game-dedicated-server-unpublished-package-join-fails` | [/fix/dedicated-server-unpublished-package-join-fails](https://sboxguide.dev/fix/dedicated-server-unpublished-package-join-fails) |
| `g-game-double-jump-set-velocity-z-directly` | [/fix/double-jump-set-velocity-directly](https://sboxguide.dev/fix/double-jump-set-velocity-directly) |
| `g-game-edit-mode-gameobject` | [/fix/edit-mode-destroy-query-lag](https://sboxguide.dev/fix/edit-mode-destroy-query-lag) |
| `g-game-editor-viewport-auto-exposure-adapts-over` | [/fix/editor-auto-exposure-screenshot-diff](https://sboxguide.dev/fix/editor-auto-exposure-screenshot-diff) |
| `g-game-first-person-hide-player-enumerate-every` | [/fix/first-person-hide-all-renderers](https://sboxguide.dev/fix/first-person-hide-all-renderers) |
| `g-game-flat-decal-geometry-clear-surface-below` | [/fix/runtime-world-building-helpers](https://sboxguide.dev/fix/runtime-world-building-helpers) |
| `g-game-full-screen-hud-toasts-banners` | [/fix/building-sbox-hud](https://sboxguide.dev/fix/building-sbox-hud) |
| `g-game-gamepad-bumper-gamepadcode-strings-switchlef` | [/fix/input-config-bindings](https://sboxguide.dev/fix/input-config-bindings) |
| `g-game-greedy-voxel-mesher-colours-cliff-skirt` | [/fix/greedy-mesher-cliff-vertical-stripes](https://sboxguide.dev/fix/greedy-mesher-cliff-vertical-stripes) |
| `g-game-headless-dotnet-build-code-project` | [/fix/dotnet-build-misses-razor-errors](https://sboxguide.dev/fix/dotnet-build-misses-razor-errors) |
| `g-game-input-usingcontroller-real-public-bool` | [/fix/input-config-bindings](https://sboxguide.dev/fix/input-config-bindings) |
| `g-game-jump-controller-clamps-against-rising-veloci` | [/fix/double-jump-set-velocity-directly](https://sboxguide.dev/fix/double-jump-set-velocity-directly) |
| `g-game-new-input-actions-added-input` | [/fix/input-config-bindings](https://sboxguide.dev/fix/input-config-bindings) |
| `g-game-new-razor-scss-created` | [/fix/new-razor-scss-not-applied-until-restart](https://sboxguide.dev/fix/new-razor-scss-not-applied-until-restart) |
| `g-game-noclip-trace-based-kinematic-controller-stat` | [/fix/noclip-trace-controller-state](https://sboxguide.dev/fix/noclip-trace-controller-state) |
| `g-game-null-check-misses-destroyed-target-nre` | [/fix/null-check-misses-destroyed-isvalid](https://sboxguide.dev/fix/null-check-misses-destroyed-isvalid) |
| `g-game-onawake-fires-synchronously-inside-component` | [/fix/component-lifecycle-onawake-onstart](https://sboxguide.dev/fix/component-lifecycle-onawake-onstart) |
| `g-game-orient-flat-decal-box-hit-normal` | [/fix/orient-decal-to-hit-normal](https://sboxguide.dev/fix/orient-decal-to-hit-normal) |
| `g-game-prefer-runtime-world-building-over-giant` | [/fix/four-object-scene-bootstrap](https://sboxguide.dev/fix/four-object-scene-bootstrap) |
| `g-game-python-s-open-path-w-windows` | [/fix/powershell-mojibake-utf8](https://sboxguide.dev/fix/powershell-mojibake-utf8) |
| `g-game-rigidbody-component-api` | [/fix/rigidbody-component-api](https://sboxguide.dev/fix/rigidbody-component-api) |
| `g-game-rolling-slopes-idempotent-ground-snap-still` | [/fix/ground-snap-pops-on-rolling-slopes](https://sboxguide.dev/fix/ground-snap-pops-on-rolling-slopes) |
| `g-game-rotation-fromyaw-angle-left` | [/fix/rotation-fromyaw-is-ccw](https://sboxguide.dev/fix/rotation-fromyaw-is-ccw) |
| `g-game-runtime-meshes-mesh-model` | [/fix/heavy-work-no-hitches](https://sboxguide.dev/fix/heavy-work-no-hitches) |
| `g-game-runtime-world-root-torn-down-gameobject` | [/fix/deferred-destroy-edit-mode-overlap](https://sboxguide.dev/fix/deferred-destroy-edit-mode-overlap) |
| `g-game-scene-getallcomponents-t-return-disabled-com` | [/fix/getallcomponents-skips-disabled](https://sboxguide.dev/fix/getallcomponents-skips-disabled) |
| `g-game-scene-json-details` | [/fix/four-object-scene-bootstrap](https://sboxguide.dev/fix/four-object-scene-bootstrap) |
| `g-game-session-reset-static-facades-component-their` | [/fix/component-lifecycle-onawake-onstart](https://sboxguide.dev/fix/component-lifecycle-onawake-onstart) |
| `g-game-single-tick-groundcheck-flicker-re-fires` | [/fix/single-tick-ground-flicker-landing-vfx](https://sboxguide.dev/fix/single-tick-ground-flicker-landing-vfx) |
| `g-game-stylesheet-many-selectors-simultaneously-dec` | [/fix/font-size-glyph-corruption](https://sboxguide.dev/fix/font-size-glyph-corruption) |
| `g-game-system-array-clone-blocked` | [/fix/array-clone-blocked-whitelist](https://sboxguide.dev/fix/array-clone-blocked-whitelist) |
| `g-game-teleport-body-over-geometry-fixed-offset` | [/fix/kinematic-movement-startedsolid](https://sboxguide.dev/fix/kinematic-movement-startedsolid) |
| `g-game-textentry-ontextedited-action-string` | [/fix/textentry-ontextedited-needs-block-lambda](https://sboxguide.dev/fix/textentry-ontextedited-needs-block-lambda) |
| `g-game-there-public-action-analog-trigger-axis` | [/fix/no-analog-trigger-axis-api](https://sboxguide.dev/fix/no-analog-trigger-axis-api) |
| `g-game-trace-api-works` | [/fix/kinematic-movement-startedsolid](https://sboxguide.dev/fix/kinematic-movement-startedsolid) |
| `g-game-trace-based-kinematic-controller-has-collide` | [/fix/trace-kinematic-no-trigger](https://sboxguide.dev/fix/trace-kinematic-no-trigger) |
| `g-game-trace-based-movement-trap-player-permanently` | [/fix/kinematic-movement-startedsolid](https://sboxguide.dev/fix/kinematic-movement-startedsolid) |
| `g-game-whitespace-immediately-adjacent-tag-expressi` | [/fix/razor-whitespace-tag-boundary-collapse](https://sboxguide.dev/fix/razor-whitespace-tag-boundary-collapse) |
| `g-perf-editor-embedded-play-mode-hard-capped` | [/fix/editor-play-mode-vsync-capped](https://sboxguide.dev/fix/editor-play-mode-vsync-capped) |
| `g-rig-animated-models-use-modelmodifier` | [/fix/fbx-export-recipe](https://sboxguide.dev/fix/fbx-export-recipe) |
| `g-rig-animgraph-heavier-alternative-needed-cross-f` | [/fix/crossfade-without-animgraph](https://sboxguide.dev/fix/crossfade-without-animgraph) |
| `g-rig-blend-duration-comes-vmdl-s-clip` | [/fix/crossfade-without-animgraph](https://sboxguide.dev/fix/crossfade-without-animgraph) |
| `g-rig-blender-fbx-export-recipe-works` | [/fix/fbx-export-recipe](https://sboxguide.dev/fix/fbx-export-recipe) |
| `g-rig-blender-s-obj-importer-puts-y` | [/fix/rigging-ai-generated-mesh](https://sboxguide.dev/fix/rigging-ai-generated-mesh) |
| `g-rig-bone-heat-auto-weights-fail-wholesale` | [/fix/rigging-ai-generated-mesh](https://sboxguide.dev/fix/rigging-ai-generated-mesh) |
| `g-rig-bone-procedural-override-setbonetransform-un` | [/fix/setbonetransform-silently-noop](https://sboxguide.dev/fix/setbonetransform-silently-noop) |
| `g-rig-citizen-addon-source-vmdl-schema-reference` | [/fix/fbx-export-recipe](https://sboxguide.dev/fix/fbx-export-recipe) |
| `g-rig-mixamo-mocap-retargets-onto-npc-lane` | [/fix/mixamo-retarget-custom-rig](https://sboxguide.dev/fix/mixamo-retarget-custom-rig) |
| `g-rig-model-compiler-sanitizes` | [/fix/bone-name-dot-to-underscore](https://sboxguide.dev/fix/bone-name-dot-to-underscore) |
| `g-rig-naturalistic-mocap-idles-don-t-loop` | [/fix/mixamo-retarget-custom-rig](https://sboxguide.dev/fix/mixamo-retarget-custom-rig) |
| `g-rig-pace-looping-locomotion-clips-clip-s` | [/fix/pace-locomotion-clips-by-stride](https://sboxguide.dev/fix/pace-locomotion-clips-by-stride) |
| `g-rig-physics-shape-coords-same-unit-mesh` | [/fix/ragdoll-scripted-rig-npc](https://sboxguide.dev/fix/ragdoll-scripted-rig-npc) |
| `g-rig-scripted-keyframes-keep-quaternion-keys-hemi` | [/fix/quaternion-hemisphere-continuity](https://sboxguide.dev/fix/quaternion-hemisphere-continuity) |
| `g-rig-scripted-rig-npc-ragdoll-engine-physics` | [/fix/ragdoll-scripted-rig-npc](https://sboxguide.dev/fix/ragdoll-scripted-rig-npc) |
| `g-rig-skinnedmodelrenderer-sequence-blending-bool` | [/fix/crossfade-without-animgraph](https://sboxguide.dev/fix/crossfade-without-animgraph) |
| `g-rig-skinnedmodelrenderer-setik-animgraph-gated` | [/fix/setbonetransform-silently-noop](https://sboxguide.dev/fix/setbonetransform-silently-noop) |
| `g-rig-transform-apply-scale-true-mixamo-armature` | [/fix/mixamo-retarget-custom-rig](https://sboxguide.dev/fix/mixamo-retarget-custom-rig) |
| `g-rig-two-renderer-manual-cross-fade-wrong` | [/fix/crossfade-without-animgraph](https://sboxguide.dev/fix/crossfade-without-animgraph) |
| `g-rig-vmdl-physics-node-schema-copy-citizen` | [/fix/ragdoll-scripted-rig-npc](https://sboxguide.dev/fix/ragdoll-scripted-rig-npc) |
| `g-tool-angles-struct-fields-lowercase` | [/fix/angles-struct-lowercase-fields](https://sboxguide.dev/fix/angles-struct-lowercase-fields) |
| `g-tool-boxcollider-center-scale-always` | [/fix/capsule-vs-box-collider-choice](https://sboxguide.dev/fix/capsule-vs-box-collider-choice) |
| `g-tool-deriving-visual-s-facing-horizontal-velocity` | [/fix/velocity-facing-pendulum-flip](https://sboxguide.dev/fix/velocity-facing-pendulum-flip) |
| `g-tool-dotnet-build-warning-counts-lie-under` | [/fix/dotnet-build-vs-whitelist](https://sboxguide.dev/fix/dotnet-build-vs-whitelist) |
| `g-tool-editor-compiler-crash-internally-nullreferen` | [/fix/stale-assembly-hotload](https://sboxguide.dev/fix/stale-assembly-hotload) |
| `g-tool-engine-console-noise-normal` | [/fix/first-play-compile-checklist](https://sboxguide.dev/fix/first-play-compile-checklist) |
| `g-tool-engine-ships-own-built-mcptool-s` | [/fix/engine-mcptool-source-reference](https://sboxguide.dev/fix/engine-mcptool-source-reference) |
| `g-tool-everything-broke-once-during-agent-waves` | [/fix/stale-assembly-hotload](https://sboxguide.dev/fix/stale-assembly-hotload) |
| `g-tool-facingyawoffset-mesh-facing-correction-swaps` | [/fix/facing-yaw-offset-axis-swap](https://sboxguide.dev/fix/facing-yaw-offset-axis-swap) |
| `g-tool-fixing-source-asset-always-trigger-recompile` | [/fix/failed-asset-recompile-stale-cache](https://sboxguide.dev/fix/failed-asset-recompile-stale-cache) |
| `g-tool-hotload-csharp-edits-apply` | [/fix/editor-hotload-expectations](https://sboxguide.dev/fix/editor-hotload-expectations) |
| `g-tool-kenney-s-own-nature-pack-drive` | [/fix/kenney-cc0-import](https://sboxguide.dev/fix/kenney-cc0-import) |
| `g-tool-model-load-missing-vmdl-return-error` | [/fix/model-load-missing-returns-error-mesh](https://sboxguide.dev/fix/model-load-missing-returns-error-mesh) |
| `g-tool-new-system-random-time-seeded-whitelisted` | [/fix/dotnet-build-vs-whitelist](https://sboxguide.dev/fix/dotnet-build-vs-whitelist) |
| `g-tool-powershell-5-1-corrupts-utf-8` | [/fix/editing-razor-byte-safe](https://sboxguide.dev/fix/editing-razor-byte-safe) |
| `g-tool-runtime-reflection-also-whitelist-banned` | [/fix/dotnet-build-vs-whitelist](https://sboxguide.dev/fix/dotnet-build-vs-whitelist) |
| `g-tool-s-box-whitelist-enforced-editor-compiler` | [/fix/dotnet-build-vs-whitelist](https://sboxguide.dev/fix/dotnet-build-vs-whitelist) |
| `g-tool-sbproj-org-valid-lowercase-package-ident` | [/fix/sbproj-title-ident-startup](https://sboxguide.dev/fix/sbproj-title-ident-startup) |
| `g-tool-some-csharp-source-files-crlf` | [/fix/powershell-mojibake-utf8](https://sboxguide.dev/fix/powershell-mojibake-utf8) |
| `g-tool-sounds-assets-compiled-after-session-started` | [/fix/custom-sound-wont-play](https://sboxguide.dev/fix/custom-sound-wont-play) |
| `g-tool-stalled-steam-update-half-deletes-s` | [/fix/stalled-steam-update-recovery](https://sboxguide.dev/fix/stalled-steam-update-recovery) |
| `g-tool-static-input-gates-leak-across-play` | [/fix/component-lifecycle-onawake-onstart](https://sboxguide.dev/fix/component-lifecycle-onawake-onstart) |
| `g-tool-static-registry-survives-play-restart-gate-on-live-objects` | [/fix/static-registry-survives-play-restart](https://sboxguide.dev/fix/static-registry-survives-play-restart) |
| `g-tool-steam-update-s-box-engine-underneath` | [/fix/stale-assembly-hotload](https://sboxguide.dev/fix/stale-assembly-hotload) |
| `g-tool-verify-compiles-editor` | [/fix/project-setup-skeleton](https://sboxguide.dev/fix/project-setup-skeleton) |
| `g-tool-whitelist-http-may-call` | [/fix/dotnet-build-vs-whitelist](https://sboxguide.dev/fix/dotnet-build-vs-whitelist) |
| `g-ui-buildhash-razor-re-render-trigger` | [/fix/ui-frozen-buildhash](https://sboxguide.dev/fix/ui-frozen-buildhash) |
| `g-ui-draggable-slider-tracks-click-jump-drag` | [/fix/draggable-slider-click-drag](https://sboxguide.dev/fix/draggable-slider-click-drag) |
| `g-ui-flex-grow-track-holding` | [/fix/flex-grow-percentage-child-feedback-loop](https://sboxguide.dev/fix/flex-grow-percentage-child-feedback-loop) |
| `g-ui-font-glyph-corruption-is-cumulative-text-count-not-just-font-size` | [/fix/font-glyph-corruption-cumulative-text-count](https://sboxguide.dev/fix/font-glyph-corruption-cumulative-text-count) |
| `g-ui-freshly-scaffolded-project-s-code-assembly` | [/fix/scaffold-missing-global-usings](https://sboxguide.dev/fix/scaffold-missing-global-usings) |
| `g-ui-gameobject-networkmode-defaults-snapshot` | [/fix/owner-simulated-networking](https://sboxguide.dev/fix/owner-simulated-networking) |
| `g-ui-interface-based-scene-scans-unreliable` | [/fix/interface-scan-returns-nothing](https://sboxguide.dev/fix/interface-scan-returns-nothing) |
| `g-ui-jetbrains-mono-consolas-shipped-s-box` | [/fix/engine-monospace-roboto-mono](https://sboxguide.dev/fix/engine-monospace-roboto-mono) |
| `g-ui-json-serialize-deserialize-t` | [/fix/saveload-without-drift](https://sboxguide.dev/fix/saveload-without-drift) |
| `g-ui-name-classes-after-sandbox-built-ins` | [/fix/assembly-cs-globals-setup](https://sboxguide.dev/fix/assembly-cs-globals-setup) |
| `g-ui-panelcomponent-overrides-ontreebuilt-ontreef` | [/fix/panelcomponent-ontreebuilt-lifecycle](https://sboxguide.dev/fix/panelcomponent-ontreebuilt-lifecycle) |
| `g-ui-razor-files-go-global-namespace` | [/fix/assembly-cs-globals-setup](https://sboxguide.dev/fix/assembly-cs-globals-setup) |
| `g-ui-ref-field-bare-private-field-silently` | [/fix/ref-field-private-field-never-assigns](https://sboxguide.dev/fix/ref-field-private-field-never-assigns) |
| `g-ui-runtime-texture-ui-panel` | [/fix/runtime-texture-ui-panel](https://sboxguide.dev/fix/runtime-texture-ui-panel) |
| `g-ui-sibling-panelcomponent-s-gameobject-have-imp` | [/fix/building-sbox-hud](https://sboxguide.dev/fix/building-sbox-hud) |
| `g-ui-sync-owner-proxies-sync-syncflags` | [/fix/owner-simulated-networking](https://sboxguide.dev/fix/owner-simulated-networking) |
| `g-ui-textentry-raw-html-input-house-control` | [/fix/textentry-not-html-input](https://sboxguide.dev/fix/textentry-not-html-input) |
| `g-ui-write-inside-already-open-razor-code` | [/fix/nested-razor-code-block-rz1010](https://sboxguide.dev/fix/nested-razor-code-block-rz1010) |

## Pack-only gotchas (in the checklist, no full article)

- `g-art-camera-screenshot-renders-through-real-scene`
- `g-art-correct-sub-part-positions-prove-nothing`
- `g-art-dedicated-ambient-light-gradient-fog-compone`
- `g-art-forge-tripo-vehicle-shaped-mesh-s`
- `g-art-generated-obj-vmdl-recipe-blender`
- `g-art-lock-camera-exposure-kill-auto-exposure`
- `g-art-make-ground-alive-swap-flat-tile`
- `g-art-materialoverride-replaces-tint-path-box-prop`
- `g-art-mathf-has-lerp-engine-s`
- `g-art-mission-control-s-forge-auto-deliver`
- `g-art-model-top-ui-markers`
- `g-art-modelrenderer-tint-multiplies-usable`
- `g-art-pointlight-usable-game-component-even-siblin`
- `g-art-regenerated-ai-textures-need-editor-kick`
- `g-art-s-box-obj-import-plain-y`
- `g-art-shaders-complex-shader-supports`
- `g-art-tiling-ground-texture-will-repeat-across`
- `g-art-vmat-essentials-shader-shaders`
- `g-art-yaw-rotated-rectangle-s-axis-aligned`
- `g-audio-ambient-emitters-kiosk-jingles`
- `g-audio-elevenlabs-sfx-cost-character-cost-response`
- `g-audio-elevenlabs-voices-npc-dialogue-use-tts`
- `g-audio-speaker-line-cooldown`
- `g-audio-voice-input-action-not-universal`
- `g-game-adding-sheer-mesa-cliff-terrain-silently`
- `g-game-altitude-driven-biome-gradients`
- `g-game-arcade-raycast-car-stepped-voxel-terrain`
- `g-game-autopilot-progress-metrics-state-gated`
- `g-game-candidate-selector-s-nearest-reach-fallback`
- `g-game-cell-hash-dither-elevation-band-edges`
- `g-game-cell-minimum-depth-gate-flood-filled`
- `g-game-citizen-animgraph-already-has-native-slide`
- `g-game-citizen-clothing-folder-file-names-lie`
- `g-game-climbable-stair-step-rises-1-1`
- `g-game-clothing-engine-ships-221-local-citizen`
- `g-game-coherent-region-patches-noise`
- `g-game-collider-co-moves-swing-arc-invisible`
- `g-game-collision-fidelity-cellsize`
- `g-game-compile-status-returns-isbuilding-compilers`
- `g-game-constant-face-atlas-uv-positive-trick`
- `g-game-containment-settle-lowers-water-alternated-m`
- `g-game-decal-box-splatted-projectile-s-raw`
- `g-game-deriving-vertical-skirt-quad-winding-verifie`
- `g-game-deterministic-content-hash-same-spec-same`
- `g-game-dirty-chunk-remesh-seam-law`
- `g-game-don-t-smooth-longitudinal-slip-adds`
- `g-game-edit-mode-scene-trace-blind-runtime`
- `g-game-editor-console-buffer-2000-entries-rolls`
- `g-game-editor-mcp-editor-camera-screenshot-renders`
- `g-game-editor-mcp-port-editor-configurable-editor`
- `g-game-flat-topped-mesas-heightfield-need-two`
- `g-game-forge-tripo-vehicle-meshes-re-exported`
- `g-game-freshly-generated-vmat-vmdl`
- `g-game-greedy-meshing-delivers-1`
- `g-game-ground-vehicle-fall-through-audit-coarse`
- `g-game-hex-hash-constant-top-bit-set`
- `g-game-invisible-grab-point-registration-phantom-sp`
- `g-game-jet-ski-single-point-buoyancy-grid`
- `g-game-land-vehicle-needs-hard-deck-drowned`
- `g-game-low-frequency-mountain-mass-mask-wavelength`
- `g-game-mcp-camera-screenshot-captures-engine-s`
- `g-game-mcp-play-mode-iteration`
- `g-game-monotonic-invariant-proven-float-constructio`
- `g-game-mouse-visible-true-past`
- `g-game-multiple-panelcomponent-s-gameobject-under-s`
- `g-game-nearest-centerline-corridor-stamping-leaves`
- `g-game-networkspawn-owner-sim-host-onactive`
- `g-game-orbiting-physics-root-around-bar-makes`
- `g-game-over-world-ui-name-labels-health`
- `g-game-play-mode-terrain-brush-s-lower`
- `g-game-priority-flood-depression-fill-noisy-terrain`
- `g-game-project-mcptool-s-take-string-json`
- `g-game-proof-grade-aimed-bot-grab-window`
- `g-game-regenerating-strata-atlas-png-new-cell`
- `g-game-rest-position-spacing-cannot-clear-swinging`
- `g-game-root-gameobject-named-editor-camera-bare`
- `g-game-s-box-edit-mode-envmapprobe-ambient`
- `g-game-s-box-editor-s-mcp-server`
- `g-game-s-box-mcp-tool-registry-two`
- `g-game-scaled-citizen-foot-slides-unless-feed`
- `g-game-sea-level-slider-nothing-until-exceeds`
- `g-game-shared-multi-agent-working-tree`
- `g-game-size-step-up-step-down-glue`
- `g-game-slide-slope-logic-stepped-coarse-collision`
- `g-game-snap-ground-detach-air-slide-free`
- `g-game-snow-climate-band-gate-absolute-altitude`
- `g-game-spawn-raycast-car-suspension-equilibrium-hei`
- `g-game-spin-bar-s-release-aim-within`
- `g-game-standing-still-bounce-fall-through-audit`
- `g-game-static-facades-bridge-editor-mcptools-play`
- `g-game-steepest-descent-rivers-stall-mid-slope`
- `g-game-sticktoground-snapping-z-trace`
- `g-game-suspension-forces-along-contact-normal-body`
- `g-game-swim-voxel-world-narrow-river-triggers`
- `g-game-swing-grab-anchor-needs-visible-dressing`
- `g-game-tower-platform-geometry-isolated-swing-web`
- `g-game-trace-ground-snap-adds-fixed-offset`
- `g-game-trace-hit-exposes-physics-body`
- `g-game-translucent-splat-models-dev-box-vmdl`
- `g-game-translucent-water-film-over-bright-warm`
- `g-game-two-special-case-water-rules-correct`
- `g-game-two-water-audits-conflict-sea-boundary`
- `g-game-verified-up-facing-winding-c-b`
- `g-game-verify-mesh-import-scale-pipeline-engine`
- `g-game-visual-adjacency-laws-x-read-touching`
- `g-game-visual-z-smoothing-kill-staircase-pops`
- `g-game-wb-generate-leaves-transient-wb-world`
- `g-game-which-movement-mode-surface-allow-gate`
- `g-perf-chunked-runtime-mesh-generator-regen-single`
- `g-perf-fps-probe-measurement-hygiene-through-mcp`
- `g-perf-voxel-grain-cellsize-nearly-free-density`
- `g-rig-new-npc-clip-add-humanoid-clips`
- `g-rig-opt-additive-authoring-editing-read-riglib`
- `g-rig-pair-procedural-whole-body-rotation-clip`
- `g-tool-aimed-bot-grabbing-through-scored-best`
- `g-tool-arch-slope-tilt-axis-rotate-about`
- `g-tool-array-clone-whitelist-forbidden`
- `g-tool-bar-s-release-aimed-within-spin`
- `g-tool-blender-materials-clear-materials-new-name`
- `g-tool-build-time-tag-scans-blind-children`
- `g-tool-camera-switches-focus-target-follow-distance`
- `g-tool-copied-trace-exclusion-filters-invert-meanin`
- `g-tool-coplanar-overlay-ribbons-z-fight-give`
- `g-tool-cross-assembly-hotreload-missingmethod`
- `g-tool-editor-ignores-external-edits-persisted-sett`
- `g-tool-editor-mcp-server-s-enable-port`
- `g-tool-filesystem-data-multifile-api-whitelisted`
- `g-tool-free-penned-ai-widening-public-wander`
- `g-tool-hysteresis-lives-consumer-stateless-predicat`
- `g-tool-input-press-consumed-bottom-fixed-tick`
- `g-tool-nearest-best-pickers-need-honest-empty`
- `g-tool-publish-live-mutable-static-lists-frame`
- `g-tool-pure-nearest-target-selection-re-grabs`
- `g-tool-reusing-another-project-s-assets-copy`
- `g-tool-s-box-editor-runs-mcp-server`
- `g-tool-self-swept-projectile-separate-did-hit`
- `g-tool-shared-multi-agent-working-tree-agent`
- `g-tool-shot-commandeer-suspend-competing-drivers-sw`
- `g-tool-soundhandle-spin-up-freshly-played-handles`
- `g-tool-system-text-json-nodes`
- `g-tool-telemetry-boot-line-gated-behind-debug`
- `g-tool-third-person-camera-occlusion-ease-asymmetri`
- `g-tool-threshold-pair-event-detectors-die-smooth`
- `g-tool-visual-pin-hands-feet-world-feature`
- `g-ui-camera-screenshot-s-ui-overlay-renders`
- `g-ui-client-local-screen-effect-fullscreen-fade`
- `g-ui-css-keyframes-animation-supported`
- `g-ui-defer-overlay-before-sync-blocking-call`
- `g-ui-editor-generated-csproj-gitignored`
- `g-ui-loose-json-under-assets`
- `g-ui-mouse-visible-true-obsolete`
- `g-ui-razor-collection-stateful-child-panels-don`
- `g-ui-runtime-clipboard-api-reachable-game-code`
- `g-ui-scenepanel-ui-3d-model-preview-world`
- `g-ui-screenpanel-zindex-cross-panel-stacking`
- `g-ui-scss-import-shared-token-mixin-file`

## Articles without a gotchas.md source (11)

_Written from the other private docs; tracked so the sync won't recreate them._

`agent-file-ownership-discipline`, `ai-agents-build-game-in-a-day`, `cloud-assets-fail-under-load`, `loose-resource-files-publish`, `package-references-clean-start`, `play-fund-explained`, `pre-publish-checklist-sbox-game`, `sandbox-services-wiring`, `sbox-project-folder-layout`, `singleton-no-reference-wiring`, `standalone-steam-export`

