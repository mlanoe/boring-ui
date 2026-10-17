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
  places the caret at the clicked cell. ASCII text only: `String.length` differs between the interpreter and `boring build`.
- Scroll wheel input is `scrollBy` (see "Composition, scrolling and effects").

Tests: `events_test.br`, `events_extra_test.br` (disabled, capture, editing, Enter/Escape). Behaviour change: a press no longer
activates (it captures); use `click` (or down + up) where a Button must fire.

Not yet: IME / composition and undo, key capture-target-bubble phases, `.focused(...)` bindings, focus scopes and
`focusOrder`/`focusable`, modal routing and `Sheet`, `List` selection, focus rings, momentum scrolling, scroll-into-view on
focus, error reporting from callbacks.

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
- Per-identity (incremental) rebuilds — `flush` conservatively rebuilds the whole window, as the draft allows;
  lifecycle *hooks as user callbacks* (`events` is a log), `onTask` and its generations, focus, animated removal,
  layout/scene/rendering (layers 3+). Write-site invalidation is explicit (`invalidate`) rather than generated.

## Running the tests

```bash
tests/run_tests.sh              # interpreter (`boring run`); needs a `boring` on PATH (cargo install --path ../boring)
tests/run_tests_transpiled.sh   # transpiler (`boring build` + `cargo run`), same files
```
