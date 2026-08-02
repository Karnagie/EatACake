# Upstream archive — settled candidates

> Where a queue row goes when it is DONE. `QUEUE.md` holds pending rows only;
> without this file the depth signal in U1b can never fall and the queue grows
> forever — which is exactly what happened here (200 rows captured between
> 2026-07-12 and 2026-08-02, none ever settled).
>
> Rows are moved here **by ID**, carrying:
> `harvested <date> <sha>` — the sha is the template commit that carries it
> (one commit per candidate, U3) — or `rejected: <reason>`.
>
> **Rejections stay here permanently**, so a future harvest cannot
> re-litigate them. `grep` here before proposing anything.

| ID | Date | Type | P | Claim + detail | Evidence | Outcome |
|---|---|---|---|---|---|---|
| — | — | — | — | *(nothing settled yet — created 2026-08-02 with the loop fix)* | — | — |
