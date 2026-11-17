# Changelog

## 1.1.0

- Add a synthetic IP reputation scale and VPN/proxy/Tor indicator in the widget and app menu, using ProxyCheck v2 after successful IP detection.
- Cache successful ratings per IPv4 for 24 hours across restarts, with up to 64 entries.
- Add a saved Preferred IP service selection: 2ip.io or icanhazip.com, with the other provider used only as fallback and separate rate-limit handling.
- Share one atomic JSON snapshot between the app and read-only widget; expired snapshots prompt users to open the app after five minutes.
- On network changes, show a question mark and Updating data..., wait three seconds, and perform one logical IP check without confirmation loops.
- Include resource-use improvements, English documentation, and current English preview images.

## 1.0.30

- Show a question mark and Updating data... immediately after a network configuration event.
- Wait three seconds after the last event, then perform one check with no automatic transition retries.
- Cancel pending checks on newer events and reject results from the previous route.

## 1.0.29

- Stop transition checks after the first successful response instead of requiring three matching IP results.
- Combine network events with a one-second settling delay; retry failures after 2, 4, and 8 seconds, up to four attempts and a 30-second overall timeout.
- Preserve Retry-After handling and shared read-only widget snapshots.

## 1.0.28

- Share one atomic JSON snapshot from the companion app to the widget; remove all networking and the country database from the extension.
- Give the sandboxed widget read-only access to the snapshot file without an App Group.
- Show Open IP Widget when the snapshot is missing, invalid, or older than five minutes, with a scheduled expiration timeline entry.
- Open/refresh the app when the widget is clicked.
- Refresh from the companion approximately every four minutes to keep healthy data inside the five-minute freshness limit.

## 1.0.27

- Recognize HTTP 429 from 2ip.io and honor Retry-After, using a one-minute fallback when absent.
- Stop stabilization immediately on rate limiting and schedule a single companion retry when allowed.
- Preserve rate-limit deadlines across widget reloads and VPN connection resets.

## 1.0.26

- Make each widget timeline reload use a fresh 2ip.io client, without carrying failures or VPN connections over from the previous timeline.
- Preserve the trailing widget reload when coalescing closely spaced updates.
- Request recovery timelines after about one minute on widget errors, and log the underlying request failures.

## 1.0.25

- Use only api.2ip.io in the app and widget to avoid inconsistent IP results under VPN split routing.
- Remove fallback requests to other IP services, including on errors and during transition checks.

## 1.0.24

- Start each transition probe immediately after the previous response or error; remove the fixed pause and minimum observation delay.
- Stop after three matching IP results, 12 attempts, or 30 seconds.
- Test sequential response handling and bounded immediate failures.

## 1.0.23

- Retry VPN/network transitions until three consecutive IP results agree, observing for at least five seconds with a 30-second timeout.
- Cancel superseded checks, refresh the current network path, and reset old VPN connections and provider cooldowns.
- Reduce idle timer wakeups, duplicate startup requests, and redundant widget reloads.
- Bound the flag cache, close owned HTTP sessions, and stream country database updates in the companion app only.
- Add regression tests for transition recovery, cancellation, timeout, and bounded GeoIP conversion.

## 1.0.22

Initial GitHub publication of IP Widget for macOS.

- Native desktop widget for public IPv4, country name, and flag.
- Immediate refresh requests on system network configuration and default-route changes.
- Menu bar companion with manual refresh and optional launch at login.
- Rotating IP providers with failover and local DB-IP country lookup.
- Automatic country database updates and English/Russian interface localization.
- Ad-hoc signed app and unsigned, unnotarized PKG installer for Apple Silicon Macs.
