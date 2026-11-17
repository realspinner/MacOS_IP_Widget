# IP providers and country data

## Public IPv4 detection

Each client rotates through this provider pool, starting at a random index:

| Endpoint | Response | Country data |
| --- | --- | --- |
| `https://api.2ip.io/` | JSON | Country code when available |
| `https://api.ipify.org?format=json` | JSON | Local database lookup |
| `https://checkip.amazonaws.com/` | Plain text | Local database lookup |

A successful check normally uses one request. A failed request advances to the next provider, with a four-second request timeout. Consecutive failures place a provider on cooldown for 1, 2, 4, 8, 16, then 32 minutes. Cancellation stops the provider traversal.

Periodic checks run approximately every five minutes, with up to 30 seconds of variation. The app and WidgetKit extension have independent clients, so running both increases total requests. Network transitions and manual refreshes can trigger additional checks. WidgetKit controls the actual widget refresh schedule.

## Country database

When the response does not include a country code, the client looks up the IPv4 address in a local [DB-IP Country Lite](https://db-ip.com/db/download/ip-to-country-lite) database. The bundled edition is November 2026, approximately 3.5 MiB, containing IPv4 ranges only.

Each binary record is ten bytes: the start and end addresses as big-endian `UInt32` values, followed by a two-letter country code. Records are sorted, non-overlapping, and searched with binary search.

The data is licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Attribution is included in the app menu and [GeoIP-NOTICE.txt](../Sources/IPWidgetCore/Resources/GeoIP-NOTICE.txt). Changes from the original dataset: IPv4-only filtering and conversion from CSV to compact binary records. Lite accuracy is limited; VPN locations describe the exit address.

## Automatic database updates

While the app or widget is active, IP detection can start a background database check at most once per day per process. The bundled month is not downloaded again when there is no cached database. A new monthly CSV archive is downloaded over HTTPS, decompressed using the system `gunzip`, and converted to the compact IPv4 table.

Updates validate range bounds, ordering, overlaps, and country-code format. The resulting table is written atomically under `~/Library/Application Support/IPWidget/GeoIP/`. Failed updates retain the last working database and can be retried the following day. Updates do not run while both the app and extension are inactive.
