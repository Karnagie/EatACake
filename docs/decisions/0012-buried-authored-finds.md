# ADR-0012 — Finds are buried authored models you dig out, not pickups that pop

Date: 2026-07-26
Status: accepted
Supersedes the pickup half of the original §6.1 treasure design.

## Context
The reward beat of a 25-45 minute cake was a 2.4-stud neon ball that appeared at
the surface when the heightfield dropped past a rolled height, waited 45 s, and
was collected by walking within 5 studs. Three problems:

1. **No dig.** The ball *appeared*; nothing about eating uncovered it. The
   genre reference (Drain the Lake) sells exactly the opposite: the object is
   already there, buried, and removing material is what reveals it.
2. **No object.** A colored sphere carries no fantasy and no rarity read.
3. **A second collection chore.** After digging you had to walk to the ball,
   which competes with the eating loop instead of rewarding it.

The user authored a set of item models under `Workspace.Items` and asked for
them to *be* the finds, ~1.5-2× player size, dug out and then auto-collected.

## Decision
A find is a **real authored model, physically present in the cake from spawn**.

1. **Library, not config art.** `Workspace.Items` (place-authored) is moved to
   `ReplicatedStorage.Assets.Items` on boot and prepared once — the ADR-0007
   pattern. Find defs may name a model; unnamed ones are dealt round-robin, so
   adding art is a drag-and-drop, never a code change.
2. **Height-driven uniform scale**, clamped on the largest extent. Height is
   what decides how much digging a find costs; the clamp stops a wide tray from
   becoming a football field and a skewer from reading as litter.
3. **Cover, not a reveal height.** `cover` = the MAX field height over the
   model's own XZ footprint. Reveal at `cover ≤ top`, free at `cover ≤ bottom`.
   The find is uncovered exactly when it *looks* uncovered — the geometry is the
   rule, so no threshold can disagree with the screen.
4. **Monotonic exposure.** Cake oozes back (the settle automaton). Letting
   that re-bury a find would punish the player for the simulation. Exposure only
   ever advances.
5. **Auto-collect on free**, to the nearest loaded participant, dealt one per
   cascade beat. No walk-to-the-ball chore, and an auto-swept layer pops its
   finds out as a cascade instead of a confusing single frame.
6. **Visibility is the cake's job, with a fade-in lead.** The model is alpha 1
   while deep and fades in `preloadLeadStuds` (9) before its crown could show —
   under cake, so the fade is invisible. No spawn hitch, no pop-in, and a
   translucent layer legitimately shows the toy inside it.
7. **The flourish is server-side.** One timed loop per collect (pop → spin →
   magnet flight), so every player sees the same moment on a shared cake.

## Consequences
- Finds are ~40 anchored, non-colliding, non-query models resident in Workspace
  for a whole cake. Cheap by construction, but the library is user-supplied:
  **model complexity is now a perf input** — worth watching if someone drops a
  10k-triangle prop in.
- `prepareTemplate` mutates the library templates (scale/anchor/attributes).
  Prepare-once-clone-cheap is worth it; the saved place is unaffected.
- Depth is dealt per BAND (round-robin over a shuffle) rather than uniformly, so
  the reward cadence now follows the pacing curve (ADR-0011) automatically: more
  layers = more finds spread over more layers, not a clump.
- The rim glow must stay `Occluded`. `AlwaysOnTop` is a treasure radar and
  deletes the dig.

## Alternatives rejected
- **Client-side collect animation** (server hides, each client animates a local
  clone): smoother network profile, but a shared cake wants a shared moment and
  it doubles the model bookkeeping.
- **Keeping the reveal-height trigger and just swapping the art**: leaves the
  "it appeared" feel — the actual complaint.
- **Physics pickup (unanchored, Touched)**: Touched races, tumbling props inside
  a deforming heightfield, and the walk-to-it chore all over again.
