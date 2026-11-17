# Synthetic IP reputation

This is an explainable reputation index, not an Anthropic score or a probability
of Claude access. Country eligibility and account state are not measured.

Data source: [ProxyCheck API](https://proxycheck.io/api/), using its HTTPS v2 endpoint.
The lookup sends only the successfully resolved public IPv4 address. No Claude
login or credentials are involved. The provider currently allows 100 anonymous queries per day, counted by the querying public IP address;
provider denial or missing fields leaves `rating check...`, never a made-up score.

Formula (rounded to whole percent, clamped to 0–100):

`100 − round(0.70 × provider risk) − strongest classification penalty`

| Classification | Penalty |
| --- | ---: |
| Hosting | 10 |
| VPN | 15 |
| Proxy | 20 |
| Tor | 25 |
| Compromised | 30 |

Use only the strongest penalty, because classifications overlap. The provider's
risk already includes classification signals; the extra penalty intentionally
makes the index more conservative. A clean risk-0 address scores 100; a VPN with
risk 73 scores 34. Scores are heuristic, not calibrated probabilities.

The UI uses a continuous red/yellow/green scale, a position marker, percent text,
and a yellow lock/shield for VPN, proxy or Tor. Missing rating shows exactly
`rating check...`. The footer remains the connection status.

Only the companion performs rating requests, after the network stabilization
routine completes successfully and an IPv4 query succeeds. Regular refreshes
are blocked during stabilization. Route changes clear the visible rating and
cancel the active task; generation and IP checks reject late results.

Successful results are cached by IPv4 for 24 hours, persisted at
`~/Library/Caches/dev.spinner.ipwidget/ip-ratings.json`, and bounded to 64 entries. Expired results are not displayed as
fresh; failed requests are not cached. HTTP 429 imposes a one-hour cooldown.

## Request and failure handling

The request uses `https://proxycheck.io/v2/<ip>?vpn=1&asn=1&risk=1&tag=0`, without an API key. The selected IP service controls IP detection, not the rating provider. Only the resolved IPv4 address is included in the reputation lookup; the service also sees the connection's source address. Requests have a ten-second request timeout and twelve-second resource timeout.

A cache hit avoids a request. A cache miss is checked only after a successful IP response; rating results are attached to the same IP in the shared JSON. Route changes cancel ongoing work and invalidate old results. Expired cache entries are ignored, and the operating system may purge the cache. HTTP 429 starts a one-hour in-process cooldown. Other failures or incomplete responses leave the rating unavailable without replacing the valid IP result.

Daily service quotas are shared with other anonymous clients using the same querying public IP, including users of the same VPN exit. Limits can change; see the provider's [current API documentation](https://proxycheck.io/api/).
