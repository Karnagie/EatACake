# Recipe: harvest upstream queue into RobloxTemplate

Run this IN the template repo (`D:\Projects\Roblox\RobloxTemplate`), on the
user's request ("сделай harvest") or when a game session offers it and the
user agrees. This is the ONLY way template code changes from game work (U2).

## Preconditions

- The template is a git repo with a clean tree (`git init` once if needed) —
  every harvest must be revertible. If git isn't available, tell the user;
  they decide whether to proceed without the safety net.
- The user names the game project path(s) to harvest from.

## Steps (per candidate, one at a time)

1. Read `<game>/docs/upstream/QUEUE.md`; list `pending` rows to the user
   with a one-line viability verdict each. The user picks (or approves all).
2. For each picked candidate, apply the U3 gates IN ORDER:
   - **Proven**: read the evidence files in the game project (delegate bulk
     reading to `codebase-scout`). If it never actually ran in the game —
     reject.
   - **General**: port with game-specific ids/values extracted to config
     (`*Data` modules / ProfileSchema defaults). Theme words, asset ids,
     tuning numbers never enter template code.
   - Standard template D1 reading applies before writing (MAP → feature doc).
   - **Reviewed**: `adversarial-reviewer` on the diff. Fix CRITICAL/WARN.
   - **Verified**: runtime change + Studio connected → `studio-verifier`.
   - **Documented**: D2 (feature doc / MAP line / registries / flow + INDEX)
     + one line in `TEMPLATE_CHANGELOG.md`.
3. Mark the queue row in the GAME project: `harvested <date>` or
   `rejected: <reason>`.
4. `git commit` per candidate (atomic, revertible).

## Rejection discipline

Reject freely — a rejection costs one line, a regression costs every future
game. Automatic rejects: style-only rewrites of working code; speculative
"might be useful"; anything that can't name the game file where it ran;
research items without primary sources.

## Pulling improvements DOWN into an existing game

Not automatic. Compare `TEMPLATE_CHANGELOG.md` entries newer than the game's
copy date; cherry-pick manually per entry (the changelog line names what to
diff). Never bulk-overwrite game files with template files.
