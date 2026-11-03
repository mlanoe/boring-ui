# boring-ui

The headless reactive core of boring-ui, the SwiftUI-flavoured GUI toolkit designed in
[`boring/docs/design-notes/boring-ui-draft.md`](../boring/docs/design-notes/boring-ui-draft.md) and tracked in
[`boring-ui-progress.md`](../boring/docs/design-notes/boring-ui-progress.md). It is **layer 2** of the draft's
implementation sequence, written in pure [Boring](../boring) (no `Cargo.toml`, no `boring.toml` — a plain
`src/` consumed through a `[deps]` path entry, like [`boring-numlib`](../boring-numlib)):

```toml
# some-project/boring.toml
[deps]
ui = "../boring-ui"
```

```boring
use ui.core.*
```

It knows nothing about windows, layout, rendering or platform input, and nothing about the *types* of views.

## What's here — [`src/core.br`](src/core.br)

| Piece | Role |
|---|---|
| `Desc` | type-erased shape of one build of a view tree: `kind`, static `site`, iteration `key`, `children`, and — for a composite view — the `View` itself, expanded lazily |
| `describe(View)` | turns a lowered `View` tree into a `Desc` tree (native views eagerly, composite views left lazy) |
| `Mounted` | a mounted node: recycled `id`, never-recycled `generation`, children, named int `slots`, and for a composite view its typed `state` (`StateBox`) |
| `Handle` | generation-checked reference to a mounted node (`handle`, `valid`, `read`, `write`) |
| `Runtime` | mounted tree + reconciliation (`apply`/`start`), hook log (`events`), errors, invalidation (`dirty`), event transactions (`beginEvent`/`endEvent`), update loop (`flush`) |
| `Builder` / `ViewBuilder` / `ViewRoot` | traits producing a fresh `Desc` / `View` for the window (`ViewRoot` adapts a `ViewBuilder`); may invalidate while building |

Semantics implemented and tested (`tests/`):

- **Identity** of a child is `(site, key)` among its siblings plus a matching `kind`. A different kind at the same
  site replaces the node (fresh id/generation/slots); equal keys at different sites are distinct; a `site` of `-1`
  falls back to the sibling index.
- **Keyed reorder** keeps ids, slots and focus-relevant identity; removing a key unmounts, reinserting it is a new
  lifetime.
- **Hook order**: unmounts first (descendants before parents, siblings reversed), then mounts in structural
  preorder, emitted only after the whole tree committed. A plain rebuild emits nothing.
- **Duplicate keys** are validated for the whole new description *before* anything mutates: the update is refused
  (recoverable, reported in `errors` with the path and both indices), the previous tree stays mounted, and the next
  valid rebuild reconciles normally. On initial mount nothing mounts.
- **Stale handles**: ids are recycled one pass after release, generations are not, so a handle to a gone node never
  aliases the node that reused its id; stale writes are no-ops and reported, stale reads return `nil`.
- **Event transactions**: writes inside `beginEvent`…`endEvent` are deduplicated (`dirty`) and produce one update
  pass when the outermost event ends; nested events join the outer one.
- **Typed state through real views** (`tests/core_views_test.br`): a lowered `view`'s `V__State` is created by
  `newState()` at mount, kept in the mounted node behind `StateBox`, and handed back to the generated
  `expand` (which downcasts it with `as V__State`) on every build — it survives parent rebuilds and keyed
  reorders and dies with its identity. A duplicate key below a composite is detected while that subtree is
  reconciled and leaves *that subtree* as it was.
- **Stable static sites** (`tests/core_sites_test.br`): in a `[View]` block with `if`/`for`, the array-block
  lowering wraps every element as `Sited(site = n, children = [element])` (`n` = its position in the block's
  source, preorder, so conditional branches get distinct numbers; a keyed loop gets one, and its iterations
  number their own items afresh). `describe` treats `Sited` as transparent — its child, at that site — so
  toggling a branch or reordering one loop never remounts what comes after it, and two keyed loops over the
  same keys are distinct identities. Identity sites are encoded collision-free: explicit `2n`, keyed default
  `-2`, positional `2i+1`.
- **Loop guard**: `flush` stops after `maxPasses` (64) consecutive passes, reports the repeatedly invalidated ids,
  clears the queue and keeps the last committed tree.

## Lifecycle hooks and scoped tasks (`OnMount`, `OnUnmount`, `OnTask`)

Ordered wrapper views in `boring.ui` (layout/paint-transparent, like every modifier); tested in
`tests/core_hooks_test.br` (interpreter and `boring build`).

- **`OnMount(onMount = …)`** runs once after the commit that created it, in structural preorder (outermost modifier
  first). Hooks of one commit run together; their writes are batched into the next update pass.
- **`OnUnmount(onUnmount = …)`** runs when the wrapper is released, descendants before parents and the innermost
  modifier first, while the node's identity is still valid. Before the first unmount hook of a retiring subtree,
  every task in it is cancelled.
- **`OnTask(id = …, onTask = (run): …)`** starts a run once the update after mount is stable (so an `OnMount` that
  removes its own subtree starts nothing). An ordinary rebuild never restarts it; a changed `id` cancels the old run
  and starts a new one without remounting anything; unmount cancels it. The body receives a `TaskRun`
  (node, node generation, task-run generation, id).
- **Staleness**: a run is current (`rt.isCurrent(run)`) only while BOTH generations match; an id change or unmount
  bumps the task-run generation first. `rt.deliver(run, host, action)` applies a late result as one event
  transaction if the run is current, and drops and reports it (`errors`) if not. The runtime cannot intercept a write
  made outside `deliver`; that call is the continuation contract.
- Tasks here are run-to-completion callbacks, not real `task` futures: a body that wants to finish "later" keeps its
  `TaskRun` and calls `deliver` when the result arrives (what a host will do). Not done: `Future.cancel()` wiring,
  error reporting from hooks/tasks, teardown-only (read-only) state access in `OnUnmount`, animated removal.

## Environment (`env`, `Provide`) and parent-supplied seeds

- **`env T name`** views are expandable. `Provide(value = x):` + children installs `x` (a struct that declares
  `as EnvValue`) for every descendant `env` field of that type; the nearest provider wins. The core threads the
  provider scope (nearest first) through reconciliation and expands a view that has `env` with `expandIn`; an
  unsatisfied `env` renders an `EnvMissing` placeholder and is reported once in `errors`. Deviations from the draft:
  providers are matched by downcast (so `T` must be a struct conforming to `EnvValue`, no primitive `env`), and there
  is no `Theme` library type or `runUI(theme = …)` yet. Test: `tests/core_env_test.br`.
- **State seeds**: `Counter(title = t, count = expensive())` seeds that identity's `state` on its first mount only; the
  argument is a lazy closure evaluated once by `newState()`, never when a description is built or on a rebuild.

## `bind` projections of keyed collection elements

```boring
view TodoList:
    state [Todo] items = [...]
    body():
        Column:
            for item in items with item.id:
                TodoRow(item = item)          # TodoRow declares `bind Todo item`
```

A child's `bind Todo item` is still a `Slot<Todo>'actor`; the parent passes a **projection slot** for the keyed element.
The lowering (`boring/src/lower_view.rs`, "bind projections") adds, per site, a hidden typed array to the parent's state
holding `{ collection slot, projection slot, base copy, key }` records. At the end of each event, before the update pass
rebuilds anything, the core asks every mounted composite view to `commitProjectionsIn` (`Runtime.commitProjections`): a
projection whose printed form differs from its base copy is written back into the collection at the element whose KEY
still matches — never an index, so a reorder between two edits cannot redirect a write. A key that is gone is a stale
projection: the write is dropped and reported in `errors`. A projection nobody edited never overwrites a parent-side
change. The registries are rebuilt by every `body()`.

- Needs a keyed loop (`for … with <key>`), a `state [T]` collection with a named element type, and a key expression that
  only uses the loop variable; otherwise a compile error explains what to write.
- Deviations from the draft: the write-back is transactional (the collection is updated at commit, not at the child's
  write), a child's change wins over a parent change to the same element in the same event, and a field projection
  (`item.title` into a native control's `bind string`) is still not a projection — `examples/todo` keeps its per-field
  `Slot`s for that. Test: `tests/core_projection_test.br` (interpreter and `boring build`).

## Layout — [`src/layout.br`](src/layout.br) (layer 3, first slice)

Headless size negotiation and placement over the mounted tree, with a deterministic fixture font
(8 wide per character, 16 tall per line) so results are exact and golden-testable. `layout(rt, w, h)` proposes
the window to the root and returns a `Placed` tree in window coordinates; `measure`/`place` are public too.

- The draft's contract: parent proposes (each axis independently unspecified = `nil`), child reports what it
  chose (a proposal is not a constraint), parent places. `Text` wraps greedily under a proposed width and reports
  its widest line; `Padding`, `Frame` (fixed / min / max), `Priority`, `Spacer`, `Row`, `Column` (spacing,
  cross-axis alignment) are implemented; composite views are transparent, `KeyedGroup`s are erased so their
  items are the stack's children.
- Stack allocation is the draft's deterministic algorithm: reserve every minimum, then water-fill by priority group
  toward each ideal, then toward each maximum; below the sum of minimums everything keeps its minimum and the stack
  overflows; with an unspecified main axis children get their ideal and spacers their themed minimum.
- Modifier order matters and is tested with the draft's examples (`width(200).padding(10)` = 220 wide,
  `padding(10).width(200)` = 200 wide with the padding centered inside).
- `TextField` has a themed fixed size (160 × 24) and is painted as a field plus its value.
- Native views reach layout as **props**: the lowering generates `viewProps()` (scalar fields, stringified; `T?`
  absent while nil) and the core keeps them on each mounted node.
- Wrappers are views (`Padding(insets = 10.0):` + indented child) and also have a **method form**:
  `Text("x").frame(width = 200.0).padding(10.0)` is sugar for the ordered wrappers
  `Padding(insets = 10.0, children = [Frame(width = 200.0, children = [Text("x")])])` (a modifier is any view with a
  `[View] children` field; method = lowerCamel view name; positional arguments take the view's other fields in
  order). Only on a receiver that is syntactically a view (a view construction or an earlier modifier), so a user
  type's own `padding()` is never captured. The draft's convenience names (`width(200)` → `frame`) are not there.

## Scene — [`src/scene.br`](src/scene.br) (layer 3, second slice)

From a `Placed` tree: a deterministic **display list** (`FillRect`, `DrawText`, `PushClip`/`PopClip`, in paint
order — a wrapper paints its own effect, then its child; a `Clip` brackets everything its child emits, overflow
included) and **hit testing** (`hitTest(root, x, y)` → the ids from the root down to the deepest node under the
point). The hit region is a node's layout bounds intersected with ancestor clips, so visible overflow never
enlarges it, and children are tested front to back. `Background(color)` and `Clip()` are wrapper views in
`boring.ui`, layout-transparent. `describe(command)` renders one line per command for golden tests.

## Renderers — [`render/`](render) (steps 0 and 1 of
[`boring-ui-renderer-draft.md`](../boring/docs/design-notes/boring-ui-renderer-draft.md))

A separate project (`render/boring.toml`, referenced as `render.<module>`; boring-ui depends on it through the root
`boring.toml`) so it builds for `--target simd|wgpu` without the view runtime. It holds
[`display_list.br`](render/src/display_list.br) (the `Command` vocabulary scenes emit), the CPU reference
rasterizer ([`raster.br`](render/src/raster.br), [`raster_font.br`](render/src/raster_font.br)) and the kernel
rasterizer ([`raster_gpu.br`](render/src/raster_gpu.br)), described below.

### Kernel rasterizer — [`render/src/raster_gpu.br`](render/src/raster_gpu.br)

`rasterizeGpu(displayList, width, height) throws` → the same `Raster`, from a one-thread-per-pixel kernel:
`encode` turns `[Command]` into two flat numeric buffers (clips baked into every command, text expanded to one
command per glyph, colours packed, opacity groups bounded to depth 4), and each thread walks the whole list in paint
order keeping its own layer stack. It is the CPU reference's twin: `render/tests/raster_gpu_test.br` renders a corpus
(fills, strokes, shadows, text, clips, nested groups) both ways and requires every channel within one LSB
(`maxDifference`). Verified under `boring run` (sequential simulation), `--target simd` and `--target wgpu`
(`render/tests/run_kernel_tests.sh`, real Metal on macOS). Naive O(pixels × commands) by design; tiling is step 2.
The Todo-frame comparison (`tests/raster_gpu_todo_test.br`) needs the view runtime: it runs under `boring run`, and
builds and passes with `boring build --target wgpu` too (the kernel targets build the view runtime since 2026-10-20).

### Tiled kernel rasterizer — [`render/src/raster_tile.br`](render/src/raster_tile.br)

`rasterizeTiled(displayList, width, height) throws` → the same `Raster` again. A workgroup owns a 16 × 16 tile (one thread per pixel). Binning is two-level: on the host, `bin` lists for every
128 × 128 super-tile the commands that can touch it, in paint order (a first version had each tile scan the whole list:
`render/bench/run_stages.sh` showed that scan was 7.5 ms of 12.8 ms of GPU time at 1920 × 1080); inside the dispatch each
tile then takes its super-tile's list in rounds of 256: each thread tests one command's bounding box against the tile,
a Hillis-Steele scan in workgroup memory (ping-ponging between two arrays, one barrier per step) gives the selected
commands their slots so the compacted list keeps paint order — no atomics, nothing nondeterministic — and every pixel
thread draws only those, with the per-pixel kernel's own evaluator. A skipped command had zero coverage on the whole
tile, so the output is **bit-identical** to the per-pixel kernel (`render/tests/raster_tile_test.br` asserts a
difference of 0, including more than one round per tile and groups that span rounds; the benchmark checks it at
1280 × 720 and 1920 × 1080 too, where several super-tiles are involved).

`render/bench/run_bench.sh` times the three on a UI-like scene (cards with shadow, face, border and three text lines).
Apple Silicon, `--target wgpu` (Metal), release build, whole call including encoding, upload, readback and packing:

| scene | CPU reference | per-pixel kernel | tiled kernel |
|---|---|---|---|
| 1280 × 720, 633 commands | 17 ms | 78 ms | **12 ms** |
| 1280 × 720, 1925 commands | 26 ms | 222 ms | **13 ms** |
| 1920 × 1080, 1925 commands | 69 ms | 562 ms | **43 ms** |

Where the tiled kernel's time goes (`render/bench/run_stages.sh`, warm, minimum of nine runs, 1925 commands):

| stage | 1280 × 720 | 1920 × 1080 |
|---|---|---|
| encode (host) | 2.1 ms | 2.0 ms |
| bin (host) | 0.14 ms | 0.14 ms |
| upload | 1.2 ms | 2.1 ms |
| GPU compute (the wait for it) | **3.6 ms** | **4.9 ms** |
| read back the picture (not needed for a window) | 2.5 ms | 3.0 ms |

The GPU part was 12.8 ms at 1080p before the super-tile lists and the single-barrier scan (flag tests 3.8 ms, scan
steps 7.5 ms, drawing only 1.5 ms: the scan, not the drawing, was the cost). On `--target simd` (the kernel emulated on
CPU threads) the tiled kernel is about 1.8 × faster than the per-pixel one but two orders of magnitude slower than the
CPU reference: that target is a portability fallback, not a renderer.

### CPU reference rasterizer — [`render/src/raster.br`](render/src/raster.br)

`rasterize(displayList, width, height)` → `Raster` (`width`, `height`, `pixels: [uint]`, `unsupported: [string]`).
It is the oracle GPU kernels will be compared against, so it favours exact semantics over speed. Pixels are
`0xAARRGGBB`, starting fully transparent. A rectangle gets exact area coverage (a half-covered pixel has alpha 0.5) and a
clip is the geometric intersection with the clip rectangle. **Blending is in linear light** (the draft's linear
working space): colours arrive sRGB-encoded, each blend decodes the destination channel to linear, adds the
premultiplied linear source, and encodes the result back, rounding to 8 bits per operation; a stored channel is the
sRGB encoding of the *premultiplied linear* value (an opaque pixel is simply its sRGB colour, which is what a window
shows) and alpha is linear. So half-white over black is `#BCBCBC` (linear 0.5), not `#808080`, which keeps
anti-aliased text weight right (`lerpColor` in the animator makes the same choice). `srgbToLinear`/`linearToSrgb`/`encode8` are public;
all 256 8-bit values round-trip. Both kernels carry the same math (`lin8`/`mixLinear`, f32): they stay within one LSB
of the CPU reference in the tests and matched it exactly on the benchmark scene, at no measurable cost (the GPU part of a
1080p frame is still about 5 ms). Colours are `#RRGGBB[AA]` plus a few named ones; an unknown token paints magenta rather than
vanishing. Implemented: `FillRect`, `StrokeRect` (inside border, four non-overlapping bands so a translucent
border blends once, clamped to half the rectangle), `PushClip`/`PopClip` and `PushOpacity`/`PopOpacity` (group
opacity: each group is drawn into its own layer and composited once, so overlapping children do not darken; groups
nest, a stray pop is ignored and a group left open is composited at the end),
`DrawShadow` (an outer shadow of the rectangle: offset by `dx`/`dy`, Gaussian-blurred with sigma = radius / 2 by the
exact box-Gaussian integral at the pixel centre, never drawn inside the rectangle itself, exact area coverage when
the radius is 0); `DrawText` (the fixture 5x7 bitmap font of [`src/raster_font.br`](src/raster_font.br): a grapheme is `displayWidth`
cells of `h / 2` by `h`, its 6x8 texel cell stretched onto the cell with exact area coverage, a hollow box for a
grapheme the font lacks); `MarkedText` (the IME composition underline: `h / 16` pixels thick, at least one, along the bottom of the composing text's
row, in the command's colour, which the scene sets to the primary text colour); `DrawImage` (the `Bitmap` (display_list.br) named by the command's `text`, decoded elsewhere, passed as `rasterizeImages(list, bitmaps, w, h)`: stretched over the rectangle, sampled bilinearly in premultiplied linear light, edge-anti-aliased like a fill; a name with no image is skipped and listed in `unsupported`; the kernels take the same list through `rasterizeGpuImages`/`rasterizeTiledImages`); every other kind is skipped and listed once
in `unsupported`.
`pixelHex(raster, x, y)` and `toPpm(raster)` (plain-text P3, over white) serve tests and debugging;
`boring run tests/render_todo_ppm.br > todo.ppm` renders the Todo application's first frame.
Tests: `render/tests/raster_test.br`, `tests/raster_todo_test.br` (interpreter and transpiled).

## Accessibility — [`src/semantics.br`](src/semantics.br) (layer 3, third slice)

A backend-neutral semantic tree from the same `Placed` tree: nodes with a stable id (the mounted id — a keyed
reorder moves the node), role, name/value/hint/heading level, window-coordinate bounds, ordered children and
actions; `describeTree` renders it for golden tests. Layout wrappers, stacks, composite views and keyed groups are
transparent (their semantic children attach to the nearest semantic ancestor, in order). `Text` is static text
(name = content); `TextField` is a text input with its required label as name, the live bound value, and
`focus`/`setValue` actions. Modifier wrappers in `boring.ui` — `AccessibilityLabel`/`Hint`/`Heading`/`Hidden`/
`Group` — are ordered: they apply to the one semantic element they wrap (otherwise an error is reported and the
nodes are kept), a label outside a group names the group, a label inside names the child, and `Hidden` drops the
subtree without touching layout. An unlabeled `TextField` is a validation error in `Semantics.errors` but stays
in the tree. Not yet: `Button`/`Toggle`/`Image`/`Video`/`Separator`/`Scroll`/`List`/`Sheet`, live regions,
`accessibilityValue`, modal scoping, selection actions, and the platform adapter.

## Error reporting — `ErrorReport` in [`src/core.br`](src/core.br)

Every problem the runtime meets is recorded twice: the bare message in `Runtime.errors` (unchanged) and a structured `ErrorReport` in
`Runtime.reports` — `kind` (`update`, `identity`, `stale`, `env`, `theme`, `projection`, `task`, `callback`, `hook`), `message`, the mounted **view
path** (`Page/Column/OnTask/Button`, the kinds from the root down), the `node`, the task-run generation `run` and a `source` (the action, hook or task id
that ran). Nothing here terminates anything: the application reporter — a host reading `rt.takeReports()` — decides presentation and fatality.

- `rt.reportFailure(kind, source, message, node)` is the dispatch boundary's entry for a failure raised by user code: writes already completed stay
  committed and the pending invalidations still run; only the report is added.
- `rt.failTask(run, message)` reports an uncaught task error **only while the run is still current**: a run cancelled by an unmount or superseded by an
  `id` change is an expected completion and is not an error (and the task stays finished — a rebuild with the same `id` does not retry it).
- `rt.pathOf(id)` gives a node's view path; `takeReports()` returns and clears the queue.

Not yet: callbacks that actually `throw` are caught by the boundary only once `boring build` supports throwing function types (task proposed — today it
works under the interpreter only), so `act`/`deliver` do not yet call `reportFailure` themselves; a view-tree `.onError` is deferred in the draft.
Test: `core_errors_test.br`.

## Sheet, focus bindings and List (layer 4/5)

Facades in `boring.ui`; tests `sheet_test.br`, `focus_binding_test.br`, `list_test.br`, and the whole acceptance app in `todo_test.br`.

- **`Sheet(isPresented = flag):`** — modal presentation in the window's presentation layer. Closed, its content is NOT mounted and it takes no
  room; presented, its content is mounted, centered in the window, and painted last (scrim, surface, content). It blocks pointer input underneath
  (`hitTest` only reaches its subtree), exposes only a `dialog` to the accessibility tree, **traps focus traversal**, and on opening remembers the
  focused control, drops pointer capture and moves focus to a `DefaultFocus` (else its first enabled control); on dismissal focus returns to the
  remembered control while it still exists and is enabled (`Runtime.openSheets`, `focusReturn`, `syncModal`). Enter / Escape and `DefaultAction` /
  `Cancel` buttons are scoped to the sheet; with no Cancel button Escape performs the ordinary dismissal (writes `false` through `isPresented`).
  Dismissing destroys the content's identity-scoped state, so a draft is fresh each time.
- **`Focused(value = flag)` / `FocusedAs(value = token, token = "a")`** wrap a control (`.focused(...)`). Per binding, after every update pass the core
  reconciles native focus and the bound value both ways: native arrival writes the binding on, an application write of `true` / the token requests focus
  (a request for an ineligible control — disabled, outside the active sheet — stays pending and is retried), the application clearing it drops focus, focus
  leaving writes it off, and with several simultaneous requests the first by structural order wins while the others are written back off. A binding
  initialised to `true` is the cross-platform initial request. Tokens are strings (the draft's enum tokens with payload are not supported).
- **`List(selection = key, onMove = …, onDelete = …):`** + a keyed `for` — a scrolling viewport over keyed rows (rows are stacked without spacing; the
  placed rows carry their iteration `key`). Single selection by key (`""` = none): a press that hits no control selects the row, Up / Down move it,
  and the update clears a selected key that no longer exists. With `onDelete` supplied Delete / Backspace call it with `[index]`; with `onMove` AltUp / AltDown
  call `onMove(from, to)` (final index); with no callback the command is not offered. Editing keys in a focused TextField win over the list commands.
  Rows keep their mounted identity across a keyed move, so row state and focus survive. The list scrolls like `Scroll` (wheel input, offset on the node).
- **Todo** (`examples/todo`): the draft's acceptance app on these pieces — `List` with selection / reorder / delete, a `Sheet` with its own draft state, `Focused` for the
  title field, `DefaultAction` (Add, disabled while the title is blank via `Disabled`) and `Cancel` (Escape). Deviations: a row's native controls bind the `Slot` fields of
  `Todo` (projecting one FIELD of a keyed element into a native control's bind is not supported), `selection` is a string key, there is no `Separator`, and a row has a
  Delete button whose callback also keeps `boring build` from deriving `PartialEq` for the view.

## Animation — [`src/anim.br`](src/anim.br), [`src/animator.br`](src/animator.br)

Headless and deterministic: nothing owns a clock, the host passes `now` (milliseconds). The application and the runtime always see the
TARGET; painting, hit testing and accessibility bounds use the animator's **presentation** between two committed layouts.

- **Primitives** (`anim.br`, a leaf module): `Animation { curve, duration, response, damping }` with `snap()`, `linear`, `easeIn`,
  `easeOut`, `easeInOut`, `spring(response, damping)`; `progress(animation, elapsed)` (a spring may overshoot and derives its own settle
  time), `reduced(animation)`, `lerp`, and `lerpColor` — colors blend in **linear light, premultiplied** (`#000000` ↔ `#FFFFFF` at 0.5 is `#BCBCBC`).
- **Transactions** (core): `rt.animate(animation, host, ():)` tags one event transaction; `rt.withoutAnimation(host, ():)` is an explicit snap that
  beats everything; `rt.takeAnimation()` / `rt.takeTriggers()` hand the metadata to the host after the update pass. `AnimationScope(curve,
  duration, value = "{x}")` fires only when its `value` changes after the first mount (never because an ancestor merely rebuilt).
  Precedence: `withoutAnimation`, then a triggered scope, then the `animate` transaction, then nothing.
- **Animator**: `commit(animator, layout, transaction, triggers, now)` per update pass, `presentation(animator, now)`, `isAnimating`.
  Retained nodes are matched by mounted id (a keyed move interpolates, it is not remove + insert) and blend x, y, w, h; an `Opacity` value,
  an `Offset` x/y and a `Background` color blend as live prop overrides. A new target arriving mid-flight starts from the CURRENT presentation;
  a non-animated update snaps.
- **Transitions**: `Transition(insertion, removal, amount, dx, dy)` with `TransitionKind` `Identity`/`Fade`/`Scale`/`Slide`. An entering
  subtree presents from its insertion state; a removed one stays as a presentation-only **ghost** (no hit testing, no semantics) until its removal
  finishes. Fade = group opacity (`Placed.alpha`, painted as `PushOpacity`/`PopOpacity`), Scale = about the subtree's center, Slide = translation.
- **Reduced motion** (`animator.reducedMotion`): animations become a short (≤ 100 ms) opacity-only cross-fade; geometry snaps; scale and slide
  transitions become fades.

Deviations from the draft: the retiring phase only keeps the DISPLAY of a removal (ghosts) — the runtime unmounts at once unless the removal is retired as above; `TransitionKind` is `Fade`/`Slide` (an `Opacity`/`Offset` variant would shadow the views); an `AnimationScope`
trigger is a string; compound transitions and a ghost retargeted mid-removal restart from their rest state; layout properties are interpolated as
placements between committed layouts rather than by re-running layout per frame. `Keyframes` curve: `keyframes(ms, times, values)` is a piecewise-linear progress through the stops (endpoints (0, 0) and (1, 1) implicit,
values may overshoot; invalid stops fall back to linear). `takeCompletion(animator, now)` is true ONCE when the latest run has finished
(a host observation, not an application lifecycle hook; a new `commit` re-arms it). **Retiring phase**: a subtree removed under an animated `Transition` (removal not `Identity`) stays mounted but frozen — out of hit testing, focus,
events and reconciliation, tasks cancelled, focus/capture released — with its `onUnmount` hooks, slots and ids kept until the host ends it
(`endRetirement(rt, host, id)`, typically on `takeCompletion`; `retiringIds`; `endRetirements` = forced teardown). Reinserting the identity
first revives the same mounted node (no second mount, no unmount; its cancelled tasks do not restart); removing an ancestor ends it with them.
**`MatchedGeometry(id)`**: a wrapper that appears while another with the same id disappears presents from the old frame to its own (children refit),
and the old one's ghost is not drawn. Tests: `retire_test.br`, `matched_test.br`. Not yet: per-property keyframe tracks, `Sheet` presentation transitions.

Tests: `anim_test.br` (curves, springs, colors, reduced motion), `animator_test.br` (transactions, scopes, retargeting, transitions, ghosts, colors).

## Theme — [`src/theme.br`](src/theme.br)

A concrete, immutable `Theme` value (not a trait, not a global) that holds only **overrides** on a built-in base, light or dark:
`Theme()` is the complete system theme, `theme.withColor(ColorRole.Accent, "#7357FF").withMetric(MetricRole.ControlRadius, 10.0)`
returns a new one and leaves the receiver alone, `asDark()` switches the base keeping the overrides. Tokens: `ColorRole` (16
roles), `MetricRole` (14), `FontRole` and `ButtonStyle` (`Primary`/`Secondary`/`Plain`/`Compact`, in `boring.ui`) and a role→style map.
`issues()` / `themeProblems(theme)` validate: colors are `#RRGGBB[AA]`, metrics finite and non-negative, font sizes positive,
style names built in.

- **Install and resolve**: `Provide(value = theme):` + children installs a theme (a `Theme` is an `EnvValue`); the nearest provider
  wins. The core resolves it onto every mounted node (`Mounted.theme`, `Placed.theme`), so layout and painting read tokens off
  the node — no signature changes. An invalid theme is reported in `Runtime.errors` and **not installed** (the subtree keeps the
  outer theme).
- **Layout uses tokens**: spacing (`StackSpacing`), spacer minimum, control padding, toggle size, text-field size,
  `MinimumHitSize` (a floor on a button/toggle, 0 by default) and **fonts** — `Text(font = .Title)` is 24 tall with a 12-wide cell
  under the system theme, and `FontRole.Body` is exactly the 8 x 16 cell the old fixture assumed, so existing goldens did not change.
- **Painting uses tokens**: `Command.color` stays the semantic token, `Command.hex` is the resolved `#RRGGBB[AA]` (a `ColorRole` name
  resolves through the theme, a literal passes through). Buttons paint with their built-in style (`Button(style = .Primary)`, or what
  the theme maps the button's role to; `Plain` is unfilled, `Compact` tightens padding).
- Deviations from the draft: `Text`/`Border`/`Shadow`/`Destructive` roles are `PrimaryText`/`ControlBorder`/`ShadowColor`/`Danger`
  (an enum variant named like a view would shadow `Text(...)`; `.Destructive` clashes with `ButtonRole`); a few headless metrics are
  added; colors are hex strings, not a `Color` type; token tables are entry lists (dictionary iteration differs under `boring build`);
  the library `Theme` name is taken, so an application's own `env` struct must be named differently.
- **Variants**: `withColorVariant(role, "light"|"dark"|"contrast", hex)` overrides one appearance (most specific wins: `contrast` while
  on, then the appearance, then an all-variants `withColor`); `withContrast(true)` switches the base to its increased-contrast
  palette; `withTextScale(x)` multiplies every font size (so measured text). Validated: scheme names, scale in (0, 5].
  `tests/theme_variants_test.br`.
- Not yet: adaptive spacing pairs, `.textScale`/`.tint` provider modifiers, custom style traits
  (`<View> body(Context)`), inherited `.buttonStyle(...)` providers, `Toggle`/`TextField` styles.

Tests: `theme_test.br` (value), `theme_scene_test.br` (nearest provider, dark base, tokens in layout/painting, styles, validation).

## Controls and events — [`src/events.br`](src/events.br) (layer 4)

`Button(label, onActivate, role)`, `Toggle(bind bool value, label)` and `TextField(bind string value, label, …, onSubmit)` are
native facades in `boring.ui`; the runtime owns their interaction and reaches the application through the `onActivate` /
`onSubmit` callbacks or the bound slot (the lowering generates `viewAct(action, arg)` and `viewHandles(action)` from each
facade's shape). Input becomes **semantic actions**; `act(rt, host, handle, action, arg)` is the accessibility entry and takes
the same path. Each runs as one event transaction — callback, window invalidation, **one** update pass — and a stale or
disabled handle is ignored.

- **Disabled**: `Disabled(value):` (or `.disabled(true)`) — a control inside takes no focus, no capture, no action and
  is skipped by Tab; it stays in layout, hit testing and the accessibility tree (`SemNode.disabled`, no actions).
- **Pointer**: `pointerDown` focuses the deepest enabled control and **captures** the pointer (generation-checked, cleared when
  the control unmounts); nothing activates yet. `pointerUp` activates a Button / toggles a Toggle only when released over the
  captured control, released elsewhere it is a cancel; `pointerCancel` drops the capture; `click` is down + up in place.
- **Keys**: Tab / ShiftTab traverse the enabled focus order; Space / Enter activate a focused Button, Space toggles a Toggle;
  **Enter** on a TextField with `onSubmit` submits (consumed), otherwise the first enabled `DefaultAction` button activates;
  **Escape** activates the first enabled `role = .Cancel` button.
- **Text editing**: caret and selection are mounted control state (`selectionOf`). `typeText` replaces the selection or inserts
  at the caret; `Backspace`, `Delete`, `Left`/`Right`/`Home`/`End`, their `Shift…` variants and `SelectAll` edit; a pointer press
  places the caret at the clicked cell. Counted in grapheme clusters; click offsets use display-width cells.
- Scroll wheel input is `scrollBy` (see "Composition, scrolling and effects").

- **Hover**: `pointerMove(rt, host, placed, x, y)` sets `rt.hover` to the deepest enabled Button / Toggle / TextField /
  Slider under the pointer (a disabled one, or anything under a modal sheet's scrim, is never hovered; one update
  pass only when it changes, `false` otherwise), `pointerLeave` clears it, it is dropped when the control unmounts or
  a sheet opens, and `layout` marks it with a live `hovered` prop. The painter shades a hovered Button (over its face,
  under its label) and a Toggle's box with the theme's `ShadowColor` (`FillRect` with color token `hover`). While a
  slider holds the pointer the same call still drags it. The Todo window forwards every pointer position.

Tests: `events_test.br`, `events_extra_test.br` (disabled, capture, editing, Enter/Escape). Behaviour change: a press no longer
activates (it captures); use `click` (or down + up) where a Button must fire.

Not yet: (nothing from this list — see "Not here yet").

## The Todo application — [`examples/todo/src/todo.br`](examples/todo/src/todo.br), [`tests/todo_test.br`](tests/todo_test.br)

The draft's first end-to-end target, running headlessly through every layer: `TodoApp` (items, selection, an
add form), `TodoRow` (toggle, editable title, Select / Up / Delete) and `NewTodoForm` (draft `state`, `bind`s to the
parent's collection, id counter and presentation flag). The test mounts it, lays it out, paints it and reads its
accessibility tree, then drives it with pointer presses, key presses, typing and semantic actions, and checks the
draft's acceptance behaviours that exist so far: adding and editing items, an empty title refused, **cancelling
destroys the uncommitted draft** (reopening shows an empty field), **reordering keeps row identity and keyboard
focus**, deleting a row unmounts it and clears focus if it was inside, the accessibility tree has no unnamed
interactive node, no runtime errors.

Deviations from the draft's sketch, each waiting on something not built: `Todo`'s editable fields are shared
`Slot`s (typed keyed-element `bind` projections are not supported — a field projection is passed through and must
already be a `Slot`); the form is a conditional branch rather than a `Sheet`; rows have Select/Up/Delete buttons
instead of a `List` with selection, `onMove`, `onDelete`; no `.focused` bindings, `Separator`, `Scroll`, fonts or
theming. Interpreter only, like the rest of the runtime.

## Separator, Slider, Image and input-method composition

- `Separator` (`.HorizontalRule`/`.VerticalRule`, spans its container), `Image(source, label)` (a `DrawImage`
  command; the label is its accessible name) and `Slider(value: Float bind, range, step)` (arrow keys / Home / End
  and a pointer drag; generated `setFloat` action) — tests in `tests/components_test.br`.
- IME: `imeUpdate(rt, host, text, caret)` sets the *marked* text of the focused, enabled `TextField` (shown at the
  caret, underlined via a `MarkedText` command, exposed as `SemNode.marked`); the bound value is untouched until
  `imeCommit` (or Enter). While composing, Enter commits and Escape cancels — they are not the field's submit nor the
  scope's default/cancel action; an empty update or focus leaving the field drops the composition. State lives in
  `Runtime.composition`. Tests: `tests/ime_test.br` (ASCII).

## Non-modal focus scopes

`FocusScope(trap = false)`, `FocusOrder(value)` (`.focusOrder`) and `Focusable(enabled)` (`.focusable`) — draft "Focus scopes
and traversal". `focusOrder(rt)` sorts siblings by ascending `FocusOrder` value (ties keep structural order), skips
`Focusable(false)` subtrees (pointer focus is unchanged), and a trapping scope wraps Tab inside it once focus is in it;
a plain scope groups without trapping. `tests/focus_scope_test.br`.

## Directional navigation

`navigate(rt, host, placed, "Left"|"Right"|"Up"|"Down")` moves focus geometrically: the current `FocusSection` first, else the
active scope (sections as one box, then the same rule inside the winner); candidates lie in the half-plane, ranked by
main-axis gap, then cross-axis offset, then traversal order. A host sends arrows here unless a focused TextField takes
them as caret keys. `tests/focus_nav_test.br`. Not here: arrow keys inside `keyPress` (it has no layout).

## Multiple selection

`MultiList(selection: bind {string}, onMove, onDelete)` is `List` with a set of selected row keys. A plain click
replaces the selection, `clickWith(..., "Toggle")` adds/removes a row, `"Range"` selects from the anchor; Up/Down
collapse to one row, ShiftUp/ShiftDown extend from the anchor, SelectAll takes every row, Delete/Backspace call
`onDelete` with the selected rows' ascending indices, and a key that leaves the model is pruned from the set. The runtime
computes the new set and writes it whole (`setSelection`); `anchor` / `cursor` are mounted slots. Selected rows of a
`List`/`MultiList` are painted with the theme's `Selection` color (a `FillRect` behind the row). `tests/multi_list_test.br`.

## Momentum scrolling

`fling(rt, placed, x, y, vx, vy)` (pixels per second) hands a swipe over to inertia on the deepest scroller under the pointer
that can still move that way; the host calls `stepMomentum(rt, host, placed, dt)` each frame (one event transaction per
call; `true` = keep scheduling frames). Friction is x0.95 per 1/60 s, inertia ends below 20 px/s or at an edge, and a wheel
event, a press or a new fling cancels it (`cancelMomentum`, `momentumActive`). It does not bubble to a parent at an edge.
`tests/momentum_test.br`.

## Scroll into view on focus

`revealFocus(rt, host, placed)` scrolls every ancestor viewport (`Scroll`, `List`, `MultiList`) of the focused control by
the minimum needed to show its bounds: innermost first, each later one seeing the control where the earlier scrolls left
it, offsets clamped to the content, a control taller than its viewport aligned to the top edge. A host calls it after a
focus change with the laid-out window (`keyPress` has no layout). `tests/focus_reveal_test.br`.

## Key dispatch phases

A key travels the path root → focused target → root (`keyPress`): CAPTURE observers (root toward the target), the target's
default behaviour (editing, activation, traversal), then BUBBLE observers (target toward the root) that see whether the
default consumed it (`KeyEvent.handled`). `stop` ends observer delivery and `prevent` suppresses the default — independent,
so an ancestor still observes a key a text field consumed. Internal API as the draft prescribes (no public modifier yet):
`rt.observeKeys(handle, capture, handler)` with a `KeyHandler` that sets `e.stop` / `e.prevent`; observers die with their
node; a throwing one is reported (`callback`, source `key`). `tests/key_phase_test.br`.

## Undo / redo

`undo(rt, host)` / `redo(rt, host)` (keys `"Undo"` / `"Redo"`, which a host maps from Cmd/Ctrl-Z) step the focused
TextField through a per-identity history (`Runtime.histories`, dropped on unmount). Every accepted edit is recorded;
consecutive single-character typing, or consecutive deletions, with the caret where the last left it form one group — a
caret move, a switch between typing and deleting, a paste/selection replacement or an IME commit starts a new one. Undo
restores the caret too and is itself an accepted binding write; an edit clears redo. A bound value that differs from what
the history last produced (an external replacement) clears it, so undo never crosses that boundary. Not here: mapping the
caret through an external replacement. `tests/undo_test.br`.

## Focus ring

`layout` marks the keyboard-focused control with a live `focused` prop; the painter then emits a `StrokeRect`
(color `focus`, theme `FocusRing`, `FocusRingWidth` outside the bounds) after the control — `tests/focus_ring_test.br`.

## Unicode text

Caret, selection and marked-text positions are grapheme-cluster indices (`graphemeCount` / `graphemeSlice`); the
fixture font measures with `displayWidth` (wide CJK/emoji = 2 cells, combining marks = 0), ellipsis truncation drops
whole clusters, and a click maps to the nearest cluster boundary (`graphemeAtCells`). Same behaviour interpreted and
transpiled — `tests/text_unicode_test.br`. A real font engine replaces the cell model with shaped advances.

## Text engine — [`text/`](text)

Real fonts, host-side only: [`swash`](https://crates.io/crates/swash) (shaping and glyph rasterization) is called directly
from Boring source (`boring.toml` `[dependencies]` and `[external_fns]`; a project using it needs both, and builds with
`boring build`, not `boring run`).

| Piece | Role |
|---|---|
| `text/src/engine.br` | `shape` (glyph ids, proportional advances, kerning and ligatures), `shapeRuns` (per-grapheme font fallback), `rasterize` / `rasterizeAt` (8-bit mask, placement, optional subpixel offset), `lineMetrics` |
| `text/src/measurer.br` | `EngineMeasurer`, a `TextMeasurer` (`src/theme.br`): `Theme(measurer = EngineMeasurer(font = bytes))` makes layout, wrapping, truncation, caret and click-to-caret use the shaped advances. The default `FixtureMeasurer` keeps the headless tests on the cell model |
| `text/src/glyph_run.br` | `GlyphCache`: shapes a string and rasterizes each (font, glyph, size, quarter-pixel pen) once into the renderer's `GlyphAtlas`; `glyphify` rewrites every `DrawText` of a display list into `DrawGlyph` commands |

The renderers take the atlas beside the list: `rasterizeWith` (CPU reference), `rasterizeGpuWith`, `rasterizeTiledWith`
(a `DrawGlyph` is an 8-bit mask blended like a rectangle, pen on the pixel grid, the subpixel position baked into the mask).
`TextField` text is clipped to the field and scrolls horizontally to keep the caret in view (`fieldScroll`, layout.br).

Tests: `text/tests/run_tests.sh`. A picture of the Todo set in Arial: `text/demo/run.sh > todo.ppm`. The Todo window
(`examples/todo_window`) runs on all of it. Not done: a measurement cache (every width reshapes the string), line breaking
and bidi through the engine, weights/italics, colour emoji, a bundled font (the paths are macOS system fonts).

## Window — [`examples/todo_window`](examples/todo_window)

The Todo application in a native window: the view runtime lays it out headlessly, its display list is encoded once
(`todoFrame`), and the tiled kernel rasterizer draws it straight into the pixel buffer `screen.present` shows (on
`--target wgpu` that buffer never goes back to the host).

```bash
examples/todo_window/run.sh     # boring build --target wgpu, then run (Escape quits)
# the window shows `assets/logo.ppm` through an `Image` view: render/src/image_file.br decodes binary PPM (P6), PNG (render/src/png.br: 8-bit, non-interlaced, inflate written in Boring) and JPEG (render/src/jpeg.br: baseline + progressive, gray/YCbCr) into a
# `Bitmap`, `encodeImages` puts its texels in the kernel's `img` buffer (the generated crate runs from main_wgpu/,
# hence the `../assets` path)
```

It is a plain `Screen` program: top-level `let`s (`frame`, `bins`) are ordinary code that runs once before the
window opens, and `TileKernel(frame.f, frame.u, ...)` takes any expression — its `init` uploads the encoded display
list, the atlas and the sizes. The compiler needs no patching of the generated crate any more.

### Window input and resize (the `Screen` event API)

A `Screen` hands the loop everything the runtime in [`src/events.br`](src/events.br) consumes, as per-frame values
(full reference: `boring/docs/gpu-display.md`, "Input" and "Resizing"; the same on `simd`/`metal`/`wgpu`/`cuda`/`rocm`):

| Runtime input (`events.br`) | `Screen` member |
|---|---|
| pointer position / click (`pointerDown`/`pointerUp`/`click`) | `screen.mouse.x`, `.y` (buffer pixels), `screen.mouse_pressed("left")`, `screen.mouse_released("left")`, `.left`/`.right`/`.middle` held |
| keys (`Tab`, `Enter`, `Escape`, `Backspace`, `Delete`, `Left`/`Right`/`Up`/`Down`, `Home`, `End`, Space) | `screen.key_repeat(name)` (press **or** OS auto-repeat — use for editing), `key_pressed`, `key_released`, `key(name)`, `screen.last_key`; the names are the ones `events.br` uses (`"Space"` is accepted for `" "`; `last_key` reports `" "`) |
| Shift / Ctrl / Alt / Cmd variants, SelectAll | `screen.shift`, `.ctrl`, `.alt`, `.meta` |
| key events in order (a slow frame loses none) | `for k in screen.key_events:` / `screen.key_up_events` (auto-repeats included) |
| typed text (`typeText`) | `screen.text` — characters typed this frame (no control characters, none while Ctrl/Cmd is held) |
| IME composition (`marked`) | `screen.marked` + `screen.marked_start`/`.marked_end` (byte offsets, `-1` = none); the committed text arrives in `screen.text`; `screen.setImeArea(x, y, w, h)` places the candidate window at the caret |
| scroll (`scrollBy`) | `screen.mouse.scroll_x`, `.scroll_y` (pixels; positive = wheel away from the user) |
| window focus | `screen.focused`, `.focus_gained`, `.focus_lost` |
| window size | `screen.width`, `.height` (live), `screen.resized` |

On resize the pixel buffer is *not* reallocated for you: re-lay out for `screen.width × screen.height`, then rebuild the
kernel for that size — on `wgpu` `k = TileKernel(frame.f, ..., screen.width, screen.height)` in the loop re-runs the
setup construction (the swapchain and blit follow), or set the size fields and re-upload the `'surface` field
(`k.out = blank(screen.width * screen.height)`); on every target a kernel built as `K(Dimension(w, h))` can be
reassigned (`k = K(Dimension(screen.width, screen.height))`). `todo_window` uses the pointer, key,
text, wheel, IME-composition and window-size rows (not the focus rows).

`examples/todo_window` is interactive: `Screen(..., redraw = "demand")` runs the loop once at start and then only on an
input event; the loop feeds `pointerDown`/`pointerUp`, `scrollBy`, `keyPress` (one call per entry of
`screen.key_events`, with the Shift/Cmd variants mapped to `events.br`'s names) and `typeText` from `screen.text`,
then re-lays out, re-encodes and re-bins the frame and assigns the kernel's arrays (`k.f = next.f`, ...) before the
dispatch. Checked headlessly with synthetic input in place of the window's events (click Add, type "Write tests",
Enter: the third row appears and the Add button keeps its focus ring); real clicks and typing in the window were
not tried here.

The window also follows resizes (`if screen.resized:` rebuilds the kernel for the new size, `k = TileKernel(frame.f, ..., screen.width, screen.height)`,
which is what re-points the presentation at the new buffer; the layout, display list and bins are computed for
`screen.width × screen.height` every frame) and handles IME composition
(`screen.marked` goes to `imeUpdate`, the text that ends a composition to `imeCommit`, an empty `marked` with a live
composition to `imeCancel`; `screen.setImeArea` puts the candidate window at the focused field's caret). The first version re-uploaded the kernel's `out` field instead
(`k.width = …; k.out = blank(…)`): the buffer was the right size but the presentation kept the old size and the dispatch
grid covered only the old window, so enlarging the window showed the old picture in a corner and a white (transparent)
rest, apparently frozen. That is a compiler gap for a presented `'unified` field (only a `'surface` field or a reassigned
kernel re-points the blit; a `'surface` field cannot be read back on the host on wgpu, which the renderer's tests need).
Both checked
the same synthetic way: a composition "nihao" shows in the New-item field, a request for a 480 × 300 window gives a
480 × 300 buffer and a re-flowed layout, and the text that ends the composition lands in the field as an edit. Not done:
animation, and the caret *inside* a composition (`screen.marked_end` is a byte offset and strings have no byte-length API, so the
caret sits at the end of the composing text).

Found while wiring it, filed as a compiler task: a top-level `mut rt = Runtime()` in a Screen program lowers to a
`&mut` of a temporary (build error; the program builds `rt` in a function instead), a host function named `release`
is mis-lowered in the loop (renamed `lift`), and `screen.mouse.scroll_x as float` as a call argument is an
unsupported expression (the function takes `float32`).

## Not here yet

- **Transpiled runtime is real, not interpreter-only** (checked 2026-10-16 against `boring` 4637855e): every
  `tests/*_test.br` — core, layout, scene, semantics, events and the Todo app — goes through `boring build` +
  `cargo run` and passes, with the same output as `boring run` (`tests/run_tests_transpiled.sh`). The generated
  `View` methods are always emitted; `lower_view::set_runtime_methods(false)` (set by `boring build`) only makes a
  `view`'s `body()` return `Arc<dyn View>` instead of `impl View`, so `expand` can return it (`'static`). State
  slots are `Arc<Mutex<Slot<T>>>` handles, so callbacks capture them by clone. Still untested in Rust: a real host
  (window/renderer) driving this code.
- Keys are strings (a lowered `for … with key` passes `"{key}"`). Unkeyed `for` loops keep positional (index)
  identity for their items.
- Views with `env` are not expandable (no environment to give them); `bind` slots work (they are inputs).
- Per-identity rebuilds: `invalidate(handle)` / `write` re-expand only the dirty composites (their last-built view +
  kept state, under their ancestors' environment; `partialPasses`, `expansions` count it). Callbacks a lowered view
  hands to a constructor (`Button(onActivate = ...)`) report to the composite that owns the `state` they touch
  (`StateOwner`/`DirtySink` in `boring.ui`; the owner is the view whose body wrote the closure, wherever the button
  ends up placed), so an action re-expands only that composite. A callback that also reaches an input, a `bind`, an
  `env` or a free function reports "everything" and a callback that reports nothing (hand-built native views, facade
  actions like a `Toggle`'s write through its `bind`) is unknown: both still rebuild the whole window, as does
  the root being dirty (`invalidateRoot`, a changed builder). Still open:
  lifecycle *hooks as user callbacks* (`events` is a log), `onTask` and its generations, focus, animated removal,
  layout/scene/rendering (layers 3+). A `bind` write by a child could report its owner too (not yet).

## Running the tests

```bash
tests/run_tests.sh              # interpreter (`boring run`); needs a `boring` on PATH (cargo install --path ../boring)
tests/run_tests_transpiled.sh   # transpiler (`boring build` + `cargo run`), same files
render/tests/run_tests.sh       # the renderer project's own tests (interpreter)
render/tests/run_kernel_tests.sh # kernel rasterizer vs CPU reference on the real simd and wgpu targets
render/bench/run_bench.sh       # CPU reference vs per-pixel vs tiled kernel timings
```

## Composite controls — [`src/controls.br`](src/controls.br)

Controls written as ordinary `view`s over `boring.ui` primitives, so they need no native facade (and no change to `boring`):
`ProgressBar(value, width, height, label)` (determinate, `value` clamped to 0...1, spoken as "label: N%") and
`SegmentedControl(selected, options, onSelect)` and `TabView(selected, titles, onSelect):` + one child per tab (only the selected child is mounted, so a left tab loses its state). `Picker(selected, options, onSelect)` (inline drop-down, own open state) `Stepper(value, min, max, onChange)`, `DisclosureGroup(title):` + children (own open state; declare its `state` before `children`, otherwise the trailing-block sugar sees the seed field as the last parameter) and `IndeterminateBar(phase)` (a clipped segment sweeping as the host advances `phase` 0...1 each frame: the animation system has no free-running loop). Tests: `tests/controls_test.br`, `tests/tabs_test.br`, `tests/picker_test.br`, `tests/indeterminate_test.br`, `tests/stepper_test.br` (interpreter and `boring build`).
Findings: a `bind` declared in a view of an imported module was not linked to the caller's `state` (fixed in `boring`'s `lower_view`, which now reads the imported files' view signatures); `selected` + `onSelect` stay as the API; `Background`/other wrappers need a child (`Spacer()` for a plain
swatch), otherwise `viewChildren` returns nil at run time.

## Popover — native view, layout/scene/events

`Popover(isPresented):` + two children: the anchor (laid out in place, it gives the popover its size) and the panel (mounted only while `isPresented`,
`core.br` `childrenOf`). `layout.br` places the panel just below the anchor, then `withPopovers` (run by `finishLayout`) moves it next to the
anchor: **above** it when it does not fit below and the window has more room above, and inside the window horizontally (`props["side"]` records
"below"/"above"). `scene.br` paints panels last (shadow + elevated surface) and `hitTest` tests them first, so a panel floats over its siblings
and outside its parents' bounds. A press outside the topmost popover (anchor and panel) or Escape dismisses it (`events.br`, the generated
`dismiss` action writes `false`); focus is not trapped (it is not a `Sheet`). `Picker` is built on it. Test: `tests/popover_test.br`.
Sideways, past the window's right edge the panel's right edge meets the anchor's (`props["edge"]` = left/right; `tests/popover_edge_test.br`). Not done: panels taller than the room on both sides (the panel is clamped to the window), `Popover` inside a `Sheet`.

## Programmatic scrolling — `Scroll(anchor, request)` and `ScrollAnchor`

`ScrollAnchor(name = "x"):` marks a place inside a `Scroll`'s content (layout-transparent); `Scroll(anchor = "x", request = n)` scrolls so that
anchor sits at the viewport's leading edge, clamped to the content (`events.br` `applyScrollRequests`). Request-driven, not value-driven: a
request above zero that differs from the last one applied to that scroller (its generation, the anchor, the number: `Runtime.scrollApplied`) is
applied once; bump `request` to scroll to the same anchor again, and a user's later scrolling is left alone. An anchor that is not laid out yet
keeps the request pending. The host calls `applyScrollRequests(rt, host, placed)` after an update (`todo_window`'s `paceFrame` does, before taking
the frame's layout). The "Jump to tabs" button of the window's Controls panel uses it. Tests: `tests/scroll_request_test.br`,
`examples/todo_window/controls_panel_test.br`. With `animated = true` the scroller glides to the anchor instead of jumping: `applyScrollRequests`
starts a `Runtime.glide`, and the host steps it with `stepGlide(rt, host, placed, dt)` each frame while `glideActive(rt)` (ease-out, the remaining
distance shrinks by 1000x per 0.4 s whatever the frame rate; a wheel, a press or a touch stops it). `todo_window` steps it in `paceMomentum`; its
Jump button glides. Test: `tests/scroll_glide_test.br`. Not done: two nested scrollers each with a request in one call (positions are read from one layout),
animated scrolling, a "bottom"/"center" alignment of the anchor.

## Tooltip — `OnHover` and `Tooltip`

`OnHover(value = flag):` (native, layout-transparent) writes into its bound `value` whether the pointer is over a control inside it: the runtime's
hover target is the deepest enabled Button, Toggle, TextField or Slider under the pointer, and `events.br` `syncHoverScopes` updates the `OnHover`
ancestors of the old and new target inside the event that changes `rt.hover` (`pointerMove`, `pointerLeave`; the generated `setBool` action).
`Tooltip(text = "..."):` + one child (`controls.br`) is a `Popover` whose panel shows `text` while that child is hovered, below it or above near the
window's bottom, after `delay` milliseconds (default 500, `Tooltip(delay = 0)` = at once). The runtime has no clock of its own: the host calls
`tickHover(rt, host, nowMs)` every frame (the first tick after the pointer enters starts the count) and keeps frames coming while `hoverWaiting(rt)`
(`OnHover(delay = …)`; the todo window does both, `pace.br` `syncHover`). Test: `tests/tooltip_test.br`. Not done: hover over non-control
content (a `Text`, an `Image`), tooltips for keyboard focus, touch long-press.


## Navigation — `NavigationStack`, `NavigationLink`, `NavigationBack`

`NavigationStack(title = "Home", names = ["a", "b"], titles = ["Page A", "Page B"]):` takes the root page as its first child and the page named
`names[i]` as child `1 + i` (`controls.br`, no native facade). It owns the path (its own `state`), shows only the top page under a bar with a
"‹ Back" button (while deeper than the root) and the page's title, and provides a `Navigator` (an `EnvValue`: `push(name)`, `pop()`, `depth`) to
everything inside. `NavigationLink(label, to)` pushes a page by name; `NavigationBack(label)` pops (disabled at the root). Pages below the top are not
mounted, so their state is dropped while covered (as `TabView`'s other tabs); a name that is not in `names` shows the root under a back button.
The window's Controls panel has a "Settings" stack. Test: `tests/navigation_test.br` (interpreter and `boring build`).
Not done: the system back gesture / Escape, push and pop animations (`Transition`), a path bound from outside (deep links), a typed
`navigationDestination(for:)` instead of names, a title bar that lives outside the stack, `NavigationSplitView`.

## Forms and menus — `Form`, `Section`, `LabeledContent`, `Menu`

`Form:` stacks `Section(header = "", footer = ""):` groups: a bold caption header, a bordered group whose rows are separated by hairlines, a caption footer
(`controls.br`, no native facade). `LabeledContent(label = "Name"):` is one row, the label leading and its control (the child) pushed to the trailing
edge. `Menu(label, items, onSelect, danger = -1)` is a button `label ▾` that opens the items in a `Popover` (below, above or sideways as the window allows);
choosing one closes it and reports its index, a press outside or Escape closes it, and the item at `danger` has the destructive role. Tests:
`tests/form_test.br`, `tests/menu_test.br` (interpreter and `boring build`); the window's Settings > Profile page uses all four. Not done: right-click
context menus (`contextMenu` on any view), submenus, separators and keyboard arrows inside a menu, a section border that follows the theme, a
`Form` that adapts to a narrow window.

## Grid — `Grid` and `equal` stacks

`Grid(columns = 3, spacing = 8.0):` lays its children out left to right, three to a row, in columns of equal width (each cell takes an equal share of
the width, a short last row keeps its columns); a row is as tall as its tallest cell. It is `controls.br` composition of `Row(equal = true)`s of `Fill`s:
`equal` is a new field of `Row` and `Column` (stdlib `ui.br`, `layout.br` `equalised`) that raises every child's ideal size along the stack's axis to the
largest, so the space left over is shared evenly. Every child is mounted (use `List` for long data). Test: `tests/grid_test.br`; the window's
Settings > About page has a three-column grid of buttons. Not done: columns of different weights or fixed widths, spanning cells, row/column
alignment per cell, a lazy (windowed) grid, a horizontal grid.

## Context menus — `ContextMenu`, `OnContext` and `contextPress`

`ContextMenu(items = [...], onSelect, danger = -1):` + one child: a secondary press (the right mouse button) anywhere inside the child opens the items in a
`Popover` below the child; choosing one closes it and reports its index (as `Menu`), a press outside or Escape closes it. It is `controls.br`
composition over the new `OnContext(bind bool value)` facade (stdlib `ui.br`, layout-transparent), which gets `true` when `contextPress(rt, host, placed, x, y)`
(`events.br`) lands inside it; `contextPress` also dismisses a presented popover on a press outside it and returns false when no `OnContext` is
under the pointer. The todo window routes the right button through it (`pace.br` `rightDown` / `rightHeld` / `rightUp`): a context menu under the
pointer takes the press, anywhere else the right button keeps standing in for a finger (drag to scroll, fling). The window's Controls panel has a
"Right-click here" menu. Test: `tests/context_menu_test.br`. Not done: opening at the pointer instead of under the child, long-press on touch,
submenus, keyboard (the menu key, Shift+F10) and arrow navigation inside the menu.

## Alerts and confirmation dialogs

`Alert` and `ConfirmationDialog` are modal composites built on `Sheet` (focus trap, Escape, focus restoration come with it).

- `Alert(isPresented, title, message, buttons, onSelect, defaultIndex = 0, cancel = -1, danger = -1)`: a row of buttons; `onSelect` gets the chosen index and the alert closes. Enter activates `defaultIndex`, Escape the `cancel` button.
- `ConfirmationDialog(isPresented, title, message, options, onSelect, cancelLabel = "Cancel", danger = -1)`: options stacked vertically plus an automatic Cancel (Escape) that closes without calling `onSelect`.

See `tests/alert_test.br`; the todo window opens them from "Ask…" and from the context menu's Delete.

## Date picker

`DatePicker(year, month, day, onChange, minYear = 1900, maxYear = 2100)` is an inline month calendar (SwiftUI's graphical style): a header with previous/next month buttons, weekday initials and a Monday-first grid of day buttons, the selected day shown as the primary button. `onChange(year, month, day)` fires when a day is chosen. Browsing months is the picker's own state (an offset from the selected month, snapping back when a day is chosen), so the date itself stays in the caller's state. Wrap it in a `Popover` for a drop-down. The calendar math (`isLeapYear`, `daysInMonth`, `weekday`) is exported from `controls.br`. Not yet: time of day, ranges, locale-dependent first weekday and month names. See `tests/date_picker_test.br`.

## Color picker

`ColorPicker(bind red, bind green, bind blue, label = "Color")` is an inline color chooser: a swatch of the current color with its `#rrggbb` value, a red / green / blue slider (0...255, whole steps) each and a row of preset colors (Red, Green, Blue, Black, White) that write all three channels. The color is the three bound floats; `colorHex(red, green, blue)` turns them into the `#rrggbb` string every color property of the toolkit takes (values are clamped and truncated). Not yet: alpha, hue/saturation/brightness controls, a hex text field, an eyedropper. See `tests/color_picker_test.br`.

## Canvas and shapes

The renderer paints rectangles (with rounded corners), text and images, so shapes are those, built from existing primitives: `Rectangle(color, width, height, radius = 0, stroke = "", strokeWidth = 1)`, `Circle(color, diameter, ...)`, `Capsule(color, width, height, ...)`, `HLine` / `VLine(color, length, thickness = 1)`. An outline is a second, inset fill under the shape's own, so a shape's fill is opaque (no hollow outlines).

`Canvas(width, height)` is a fixed-size, clipping drawing surface; its children are stacked in the top-left corner (later over earlier) and each is placed with `At(x, y)` (a paint and hit-test translation, so it never changes sizes). Children are ordinary views: shapes, text, images, even controls. A `for ... with` loop of `At`s inside a `Canvas` works (data-driven charts).

Not yet: diagonal lines, arbitrary paths, ellipses, gradients, hollow strokes (they need renderer commands, not a view-level fix). See `tests/canvas_test.br`.

## Drag and drop

The runtime owns the gesture. A press inside a `Draggable` that then moves a few points starts a drag carrying the `payload`; the pointer's release over a `DropTarget` delivers it. A chip with the `preview` text (default: the payload) follows the pointer over everything else, and Escape cancels the drag.

- `Draggable(payload, preview = "")` wraps its child; the child is dimmed while it is dragged. A drag cancels the press that started it, so a `Button` inside is not activated by being dragged (a press without movement is still a click).
- `DropTarget(onDrop, accepts = "", highlight = "#007aff30")` wraps its child; `onDrop(payload)` runs on a drop over it. Use `kind:data` payloads and `accepts = "kind"` to restrict what it takes; the child is tinted with `highlight` while any drag is over it.
- Underneath: native `DragSource(bind value, payload, preview)`, `OnDragOver(bind value)` and `OnDrop(bind value, onActivate, accepts)` (layout- and paint-transparent wrappers; a drop writes the payload into `value` and then calls `onActivate`).

Not yet: dragging between windows or from/to the operating system (files, text), touch drags (a finger drag scrolls), a custom preview view instead of the text chip, autoscroll near a scroll view's edge, keyboard- or accessibility-driven drags. See `tests/drag_drop_test.br`.

## Gestures

Three layout-transparent views (in `boring.ui`) turn a pointer or a finger into an action. They leave the press to the controls inside them, so a `Button` under an `OnTap` still works.

```
OnTap(count = 2, onActivate = ():
    self.opened()):
    Image(...)
OnLongPress(minMs = 500, onActivate = ():
    self.menu()):
    Text(content = "Hold me")
OnSwipe(value = dir, direction = "left", minDistance = 40, onActivate = ():
    self.dismissed()):
    Row(...)
```

- `OnTap`: a press and release within a few points of each other. `count` is the number of quick taps (400 ms apart at most, at one place) it waits for; it fires on the tap that reaches `count`, without delaying a single tap to rule out a double one.
- `OnLongPress`: fires once the pointer has been held still for `minMs`. It needs the host clock, so call `setClock` at presses and `tickHover` on frames (`hoverWaiting` tells the host to keep ticking). The press is then spent: its release neither taps nor activates the control under it, and moving before the delay cancels it.
- `OnSwipe`: on release after a move of at least `minDistance` points, writes the dominant direction (`left`, `right`, `up`, `down`) into the bound `value` and activates; with `direction` set only that direction counts.

A finger (`touchDown` / `touchMove` / `touchUp`) feeds the same recognizers; a drag that ends as a swipe still scrolls on its way. Not done: pinch and rotation (they need a second pointer), tap-versus-double-tap disambiguation, velocity thresholds for swipes.
