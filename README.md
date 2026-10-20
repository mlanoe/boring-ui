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
The kernel targets cannot yet build the view runtime, so the Todo-frame comparison
(`tests/raster_gpu_todo_test.br`) runs under `boring run` only.

### Tiled kernel rasterizer — [`render/src/raster_tile.br`](render/src/raster_tile.br)

`rasterizeTiled(displayList, width, height) throws` → the same `Raster` again. A workgroup owns a 16 × 16 tile (one
thread per pixel) and bins the commands itself, in the same dispatch, in rounds of 256: each thread tests one
command's bounding box against the tile, a Hillis-Steele scan in workgroup memory (two barriers per step) gives the
selected commands their slots so the compacted list keeps paint order — no atomics, nothing nondeterministic — and
every pixel thread then draws only those, with the per-pixel kernel's own evaluator. A skipped command had zero
coverage on the whole tile, so the output is **bit-identical** to the per-pixel kernel
(`render/tests/raster_tile_test.br` asserts a difference of 0, including more than one round per tile and groups that
span rounds; the benchmark checks it at 1280 × 720 and 1920 × 1080 too).

`render/bench/run_bench.sh` times the three on a UI-like scene (cards with shadow, face, border and three text lines).
Apple Silicon, `--target wgpu` (Metal), release build, whole call including encoding, upload, readback and packing:

| scene | CPU reference | per-pixel kernel | tiled kernel |
|---|---|---|---|
| 1280 × 720, 633 commands | 17 ms | 78 ms | **12 ms** |
| 1280 × 720, 1925 commands | 26 ms | 222 ms | **13 ms** |
| 1920 × 1080, 1925 commands | 69 ms | 562 ms | **43 ms** |

On `--target simd` (the kernel emulated on CPU threads) the tiled kernel is about 1.8 × faster than the per-pixel one
but two orders of magnitude slower than the CPU reference: that target is a portability fallback, not a renderer.
Where the tiled kernel's time goes (dispatch, readback, the host-side packing loop) is not profiled yet.

### Window — [`examples/todo_window`](examples/todo_window)

The Todo application in a native window, drawn by the tiled kernel straight into the buffer `screen.present` shows
(`--target wgpu`: the pixels never go back to the host). `examples/todo_window/run.sh` builds and runs it; the Todo
frame it shows is the one `tests/raster_gpu_todo_test.br` already proves bit-identical to the CPU reference on wgpu.
The tiled kernel's output field is a packed `[uint]'unified`, which `screen.present` accepts as well as `'surface`
(`rasterizeTiled` reads the same field back for tests). The Todo paints no window background of its own, so
`main.br` puts the theme's `WindowBackground` under the display list (otherwise the transparent pixels showed
black). No screen capture was possible where this was written: the kernel's output buffer was dumped and viewed
instead (all 640 × 360 pixels opaque, the Todo drawn).

What `Screen` lacks for a UI, found by building and probing this on `--target wgpu`:

| Gap | What happens |
|---|---|
| Host code in a Screen program | Only a `Screen(...)`/kernel constructor or a literal may appear at top level, and a render loop takes only kernel calls, scalar assignments and `if`s: no `let`, no host function call. The headless part (layout, display list, encode) therefore lives in functions and the kernel constructor's arguments recompute it |
| Kernel constructor | A Screen program builds its kernel with `TileKernel::new(device, queue)` and **never runs `init`**: the constructor arguments are ignored, every buffer stays empty and the window shows nothing (found the hard way: a blank window). `run.sh` adds the init (upload of the encoded list, atlas, sizes) to the generated crate |
| Module-level constants | Dropped from the generated crate (emitted as locals of `main`): `run.sh` patches `charWidth`/`unbounded` and the renderer's constants back in |
| New frame data | The display list lives in kernel array fields, and `k.colors = ...` (an array assigned in the loop) does not compile (`no field`, `screen` out of scope). A scene that changes needs the buffers replaced, so input cannot change the picture yet |
| Events | `screen.mouse.x` assigned to an `int` kernel field mismatches (`isize` vs `i32`); `screen.resized` does not compile in a loop condition on wgpu (and the surface is not reallocated on resize); there is no text input, IME, wheel or modifier state, only `key("k")` / `key_pressed("k")` with a literal key |
| Redraw | `loop:` renders every frame; there is no redraw-on-demand tied to the runtime's invalidation |

### CPU reference rasterizer — [`render/src/raster.br`](render/src/raster.br)

`rasterize(displayList, width, height)` → `Raster` (`width`, `height`, `pixels: [uint]`, `unsupported: [string]`).
It is the oracle GPU kernels will be compared against, so it favours exact semantics over speed. Pixels are
`0xAARRGGBB`, **premultiplied**, starting fully transparent. A rectangle gets exact area coverage (a half-covered
pixel has alpha 0.5) and a clip is the geometric intersection with the clip rectangle. Blending is source-over in
the encoded (sRGB) space for now — the colour-pipeline decision in the renderer draft is still open, and only
`blend` would change. Colours are `#RRGGBB[AA]` plus a few named ones; an unknown token paints magenta rather than
vanishing. Implemented: `FillRect`, `StrokeRect` (inside border, four non-overlapping bands so a translucent
border blends once, clamped to half the rectangle), `PushClip`/`PopClip` and `PushOpacity`/`PopOpacity` (group
opacity: each group is drawn into its own layer and composited once, so overlapping children do not darken; groups
nest, a stray pop is ignored and a group left open is composited at the end),
`DrawShadow` (an outer shadow of the rectangle: offset by `dx`/`dy`, Gaussian-blurred with sigma = radius / 2 by the
exact box-Gaussian integral at the pixel centre, never drawn inside the rectangle itself, exact area coverage when
the radius is 0); `DrawText` (the fixture 5x7 bitmap font of [`src/raster_font.br`](src/raster_font.br): a grapheme is `displayWidth`
cells of `h / 2` by `h`, its 6x8 texel cell stretched onto the cell with exact area coverage, a hollow box for a
grapheme the font lacks); every other kind is skipped and listed once in `unsupported` (`DrawImage`, `MarkedText`).
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

Deviations from the draft: the retiring phase only keeps the DISPLAY of a removal (ghosts) — the runtime still unmounts at once, so `onUnmount`
and slot teardown are not delayed; `TransitionKind` is `Fade`/`Slide` (an `Opacity`/`Offset` variant would shadow the views); an `AnimationScope`
trigger is a string; compound transitions and a ghost retargeted mid-removal restart from their rest state; layout properties are interpolated as
placements between committed layouts rather than by re-running layout per frame. Not yet: completion callbacks, keyframes, matched geometry, `Sheet`
presentation transitions.

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
- Not yet: adaptive spacing pairs, text scale and per-token light/dark/contrast variants, custom style traits
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

Tests: `events_test.br`, `events_extra_test.br` (disabled, capture, editing, Enter/Escape). Behaviour change: a press no longer
activates (it captures); use `click` (or down + up) where a Button must fire.

Not yet: momentum scrolling, scroll-into-view on focus.

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
