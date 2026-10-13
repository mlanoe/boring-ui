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
