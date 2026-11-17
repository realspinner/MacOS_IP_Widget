# IP providers and country data

## Public IPv4 detection

Only the companion app queries IP services. It tries the selected preferred service first:

- `https://api.2ip.io/`: JSON with IPv4 and optional country information.
- `https://ipv4.icanhazip.com/`: plain IPv4 text, using the IPv4-specific hostname to avoid IPv6 responses.

The app menu's **Preferred IP service** submenu selects either provider; the selection is saved across restarts. The other provider is used only if the preferred service fails, returns invalid/nonpublic IPv4 data, or is cooling down. Each check makes at most two sequential requests, each with a four-second timeout. Successful responses stop the chain. Country lookup for icanhazip is local.

Cooldowns and HTTP 429 Retry-After deadlines are tracked separately by provider. Network transitions bypass transport cooldowns but preserve rate limits. Selecting a provider cancels the old query and starts the normal network-stabilization flow; rating checks still run only after stabilization and a successful IP response. Different services can see different exits under split routing, so changing priority can change the displayed IP.

Periodic checks run approximately every four minutes, with up to 15 seconds of variation and timer tolerance. The widget reads the app's atomic JSON snapshot and makes no IP requests. Network transitions and manual refreshes can trigger additional checks. WidgetKit controls the actual widget refresh schedule.

## Country database

When the response does not include a country code, the client looks up the IPv4 address in a local [DB-IP Country Lite](https://db-ip.com/db/download/ip-to-country-lite) database. The bundled edition is November 2026, approximately 3.5 MiB, containing IPv4 ranges only.

Each binary record is ten bytes: the start and end addresses as big-endian `UInt32` values, followed by a two-letter country code. Records are sorted, non-overlapping, and searched with binary search.

The data is licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Attribution is included in the app menu and [GeoIP-NOTICE.txt](../Sources/IPWidgetCore/Resources/GeoIP-NOTICE.txt). Changes from the original dataset: IPv4-only filtering and conversion from CSV to compact binary records. Lite accuracy is limited; VPN locations describe the exit address.

## Automatic database updates

While the companion app is active, it can start a background database check at most once per day. The last attempt is persisted across app restarts. The widget receives the resolved country in the shared snapshot and neither loads nor downloads the database. The bundled month is not downloaded again when there is no cached database. A new monthly CSV archive is downloaded over HTTPS, decompressed using the system `gunzip`, and converted to the compact IPv4 table on a utility-priority worker. CSV rows are streamed in 64 KiB blocks; decompressed input is capped at 64 MiB and rows at 1 KiB.

Updates validate range bounds, ordering, overlaps, and country-code format. The resulting table is written atomically under `~/Library/Application Support/IPWidget/GeoIP/`. Failed updates retain the last working database and can be retried the following day. Updates do not run while the companion app is inactive.
