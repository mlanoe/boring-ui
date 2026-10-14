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
- Native views reach layout as **props**: the lowering generates `viewProps()` (scalar fields, stringified; `T?`
  absent while nil) and the core keeps them on each mounted node.
- Wrappers are views for now (`Padding(insets = 10.0):` + indented child); the `view.padding(10)` method form is
  not implemented.

## Scene — [`src/scene.br`](src/scene.br) (layer 3, second slice)

From a `Placed` tree: a deterministic **display list** (`FillRect`, `DrawText`, `PushClip`/`PopClip`, in paint
order — a wrapper paints its own effect, then its child; a `Clip` brackets everything its child emits, overflow
included) and **hit testing** (`hitTest(root, x, y)` → the ids from the root down to the deepest node under the
point). The hit region is a node's layout bounds intersected with ancestor clips, so visible overflow never
enlarges it, and children are tested front to back. `Background(color)` and `Clip()` are wrapper views in
`boring.ui`, layout-transparent. `describe(command)` renders one line per command for golden tests.

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

## Controls and events — [`src/events.br`](src/events.br) (layer 4, first slice)

`Button(label, onActivate)`, `Toggle(bind bool value, label)` and `TextField(bind string value, label, …)` are native
facades in `boring.ui`; the runtime owns their interaction and reaches the application through the `onActivate`
callback or the bound slot (the lowering generates `viewAct(action, arg)` from each facade's shape: `onActivate` →
"activate", a `bool` bind → "toggle", a `string` bind → "setText"). Input becomes **semantic actions**:
`pointerDown(rt, host, placed, x, y)` hit-tests, focuses the deepest control on the path and activates/toggles it;
`key(rt, host, name)` handles `Tab`/`ShiftTab` (focus order = structural, wrapping), `Enter`/`Space`;
`typeText` appends to the focused field; `act(rt, host, handle, action, arg)` is the accessibility entry and takes
the same path. Each runs as one event transaction — callback, window invalidation, **one** update pass — and a
stale handle is ignored. Keyboard focus lives on the `Runtime` (generation-checked, cleared when the node
unmounts); layout sizes controls from the themed constants, the scene paints them, and the semantic tree gives
them roles (`button`, `toggle`, `textField`, `focused`). Test: `tests/events_test.br` (a view whose callback
mutates its typed state, driven by pointer, keyboard and semantic actions).

Not yet: pointer release/capture/cancel, capture-target-bubble phases, disabled state, modal routing, focus rings
and `.focused` bindings, caret/selection/IME, scroll input, error reporting from callbacks, per-state-slot
invalidation (an action invalidates the whole window). Callbacks must be declared as a local `let` closure before
the block (`let bump = ():` …) — a multi-line closure argument inside an array-block item does not parse yet
(filed).

Not yet: `fill*`, `Layer`, `clip`, `Scroll`, baseline alignment, `idealWidth`, adaptive spacing pairs (one
default gap), right-to-left, device-pixel rounding, line limits/truncation — and, for the scene: borders, overlays, opacity, shadows, transforms, images, text decorations/carets,
hit shapes, modal routing.

## Not here yet

- **`boring build`.** The core and the typed-state adapter run under `boring run` only. `boring build` turns the
  generated runtime methods off (`lower_view::set_runtime_methods`): returning a native view's owned `[View]`
  children needs a by-reference story for `Box<dyn View>`, and an expanded body that borrows its mounted state
  cannot outlive the call (the draft's "callback `self` as mounted-view context" is the same problem).
- Keys are strings (a lowered `for … with key` passes `"{key}"`). Unkeyed `for` loops keep positional (index)
  identity for their items.
- Views with `env` are not expandable (no environment to give them); `bind` slots work (they are inputs).
- Per-identity (incremental) rebuilds — `flush` conservatively rebuilds the whole window, as the draft allows;
  lifecycle *hooks as user callbacks* (`events` is a log), `onTask` and its generations, focus, animated removal,
  layout/scene/rendering (layers 3+). Write-site invalidation is explicit (`invalidate`) rather than generated.

## Running the tests

```bash
tests/run_tests.sh        # needs a `boring` on PATH (cargo install --path ../boring)
```
