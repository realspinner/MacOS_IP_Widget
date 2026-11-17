# Resource use and background activity

Updated for release 1.1.0, November 17, 2026.

## Runtime design

The menu bar companion performs IP detection, country database updates, and reputation lookups. The widget reads one atomic JSON snapshot. It does not query IP providers, ProxyCheck, or DB-IP, and has no outgoing-network entitlement. This avoids duplicated requests from the app and extension.

Network configuration events immediately publish an updating snapshot. A cancellable three-second delay combines successive events; the app then performs one logical IP check. The preferred service is tried first, with at most one fallback request. A successful response is not confirmed repeatedly. A newer event cancels the old task, and generation/IP checks reject late results. Reputation is requested only after stabilization finishes successfully.

Periodic checks run approximately every four minutes, with 15 seconds of scheduling variation and timer tolerance. Dynamic-store and path notifications handle normal changes immediately; a one-minute route fingerprint timer is a fallback, with ten seconds of leeway. These timers do not request that a sleeping Mac wake.

## Request limits

| Operation | Normal behavior | Failure handling |
| --- | --- | --- |
| IP detection | One request to the preferred provider; up to two sequential requests including fallback | Four-second request/five-second resource timeout per provider; separate exponential cooldowns and HTTP 429 Retry-After deadlines |
| Network transition | One logical IP check after three seconds without a newer event | Thirty-second total bound; cancellation on new events; no confirmation loop or automatic transition retry series |
| Reputation | Cache lookup first; a request only after successful IP detection when no fresh cached rating exists | Ten-second request/twelve-second resource timeout; HTTP 429 starts a one-hour in-process cooldown; missing results stay unavailable |
| Country database | Background check at most once per day, persisted across app restarts | Last working table retained on failure; download resource timeout is 120 seconds; expensive/constrained networks are excluded |

Manual refreshes, wake events, and real network transitions add work. The preferred-service fallback may use a different route under split VPN routing. ProxyCheck's anonymous quota is shared by clients using the same querying public IP.

## Memory and disk

- The shared JSON is bounded to 16 KiB when read, written atomically, and mode 0600 inside a mode 0700 directory. The extension has read-only sandbox access to this exact file.
- Snapshot expiry is a future WidgetKit timeline entry, not a per-second timer. Once data is older than five minutes, the entry prompts the user to open the companion. WidgetKit controls rendering and may defer reloads.
- Successful reputation ratings are cached per IP for 24 hours, persisted across restarts, and bounded to 64 entries. Route changes clear the visible rating; stale results cannot attach to a new IP.
- Flag images use NSCache with a 32-entry limit and a 16 MiB bitmap-cost budget. These are eviction limits, not a hard process memory cap. Ratings are rendered as bitmaps and preserve their scale in accented mode.
- The compact country database is approximately 3.5 MiB. Decompression streams 64 KiB blocks on a utility-priority worker, caps expanded input at 64 MiB and individual rows at 1 KiB, and propagates cancellation. The widget does not load this database.
- Timers, notification observers, and owned refresh tasks are stopped when the companion terminates. Weak captures are used for callbacks. Owned IP sessions are invalidated when replaced or destroyed.

## Validation and limits

The release test run passed 69 tests in 8 suites. Coverage includes connection transitions, cancellation and stale-response rejection, delayed single checks, provider priority/fallback/rate limits, reputation calculation and caching, shared JSON freshness and permissions, and streamed country-data conversion. Release app and extension signatures are checked by the build scripts. README previews are rendered from deterministic sample data in English.

This is source-level review and regression validation, not a measured battery benchmark or an Instruments leak investigation. No battery percentage or leak-free guarantee follows from it. For measured assessment, compare CPU time, memory trends, wakeups, and Activity Monitor Energy Impact over 30–60 minutes on a stable network, then during repeated VPN transitions and sleep/wake cycles. Instruments Allocations/Leaks can check whether retained memory stabilizes after caches warm up.
