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
| `Desc` | type-erased shape of one build of a view tree: `kind`, static `site`, iteration `key`, `children` |
| `Mounted` | a mounted node: recycled `id`, never-recycled `generation`, children, named int `slots` |
| `Handle` | generation-checked reference to a mounted node (`handle`, `valid`, `read`, `write`) |
| `Runtime` | mounted tree + reconciliation (`apply`/`start`), hook log (`events`), errors, invalidation (`dirty`), event transactions (`beginEvent`/`endEvent`), update loop (`flush`) |
| `Builder` | trait producing a fresh `Desc` for the window; may invalidate while building |

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
- **Loop guard**: `flush` stops after `maxPasses` (64) consecutive passes, reports the repeatedly invalidated ids,
  clears the queue and keeps the last committed tree.

## Not here yet

- **Typed `state` slots.** The lowering in `boring` turns a `view` into plain structs (`V` + `V__State`); the core
  stores only a named-int slot map, because Boring has no downcast on trait objects to bring a typed `V__State`
  back out of an erased tree. Needs `trait_object as Struct` to become a checked optional downcast
  (filed as a task in `boring`), then a lowering↔core adapter (a `View` method describing a view as a `Desc`).
- Keys are strings (a lowered `for … with key` must stringify its `IdentityKey`); sites are explicit — the
  array-block lowering does not yet emit stable sites for `if` branches.
- Per-identity (incremental) rebuilds — `flush` conservatively rebuilds the whole window, as the draft allows;
  lifecycle *hooks as user callbacks* (`events` is a log), `onTask` and its generations, environments, focus,
  animated removal, layout/scene/rendering (layers 3+).
- `boring build`: the core runs under `boring run`; transpiling it is blocked on forwarding a trait-object
  parameter (`flush(b)` from `endEvent(b)` emits `b.clone()`) — filed as a task in `boring`.

## Running the tests

```bash
tests/run_tests.sh        # needs a `boring` on PATH (cargo install --path ../boring)
```
