# Release plan and failure contracts

Source-preview plan, 2026-10-13. Implemented code is not a signed release or proof
of Apple purchases, provider access, public HTTPS or physical-device behavior.
Release gates remain open until their real-stack scenarios below pass.

## Account and data boundaries

The phone owns its one-hour Apple-derived cloud session in device-only Keychain.
The computer owns provider credentials and a separately revocable scoped
collector grant. Watch/widgets receive sanitized quota and original timestamps,
not either credential. The server owns tier enforcement and job accounting.
Its database also stores pseudonymous identity, consent, hashes, transaction
identifiers and counters; a database leak would expose that metadata too.

Free registers 3 slots, Plus 10, Pro uncapped. Every refresh selects at most 50.
Due intervals are Free 120m, Plus 60m and Pro 20/30/60/120m. A successful early
Free batch costs one of 10 allowances per KST day, not one per account. Plus
Live allows 5 sessions per verified subscription period, Pro 5 per KST day.
The server starts Live's 30-minute deadline on first fresh measured success.
Local collection needs an online computer; iOS background and WidgetKit timing
cannot guarantee these intervals.

## Refresh completion: implemented source

1. Submit selected IDs, mode and a new idempotency UUID; validate the job's mode,
   target IDs, state and expiry. Auto may target only the due subset.
2. Poll the returned job ID every five seconds, for at most 60 seconds in the
   foreground. Each lookup rechecks the session and tenant under the owner lock.
3. `cached` means no due collection; `expired` means the lease ended. `completed`
   includes failed/stale collection, **not necessarily fresh quota**.
4. After a terminal result, perform one bounded authoritative account/snapshot
   read (its separate limit is 60 seconds). Preserve last usable data on failure.
5. Background, lock, logout and account switch cancel waiting. A polling timeout
   does not cancel or retry the server job, fabricate quota or spend a credit.
   The collector can still complete the five-minute lease; a later read sees it.

An old backend without job lookup makes waiting unavailable, not successful.
Deploy the backward-compatible status endpoint before distributing this client.
Malformed replies, foreign job IDs, changed targets and changed leases are
rejected. Observation timestamps never stand in for job identity.

## Purchases and restoration: implemented source, sale disabled on pilot

1. Read authenticated `/v2/me`. Purchases need server availability, its UUID
   `appAccountToken` and the current session; quota/provider plans grant nothing.
2. Load only the known monthly auto-renewable Plus/Pro products. Display Apple's
   localized price; Plus's intended KRW 3,990 is not a hard-coded purchase price.
   Pro price is still undecided. No product or unavailable verification means
   no purchase button. Register both products in one subscription group.
3. Purchase with that UUID; pending approval and cancellation do not grant access.
4. Require StoreKit verification and exact account ownership. Send the bounded
   signed transaction transiently to the server; never persist or log the JWS.
   The server verifies Apple signatures, app/environment, ownership and replay.
5. Finish only after a valid accepted server response. A server `free` response
   also acknowledges an expired/refunded transaction but grants no paid tier.
   Re-read `/v2/me`; the purchase model never assigns Plus/Pro itself.
6. Keep the update listener for app lifetime. Recover unfinished transactions and
   current entitlements once on a new configured session. Explicit Restore alone
   calls `AppStore.sync`; ordinary quota reads do not repeatedly upload receipts.
7. Deduplicate the same in-flight transaction, but retain newer signed updates
   (including refund/revocation) for another pass. Logout/server/session/account
   changes invalidate completions and clear queued receipts/products.
8. Network/server failure leaves delivery unconfirmed for reconnect/Restore;
   new unfinished transactions are not finished. Different-cloud-account purchases
   are refused, not silently transferred. Account erasure does not cancel Apple's subscription; link to
   Apple's subscription management and explain this before purchase/erasure.

Account erasure followed by a new cloud registration creates a new UUID. The
current implementation consequently refuses an old subscription's account token,
even for the same Apple sign-in. Define and validate an authenticated recovery
policy before opening sales; never bypass ownership or retain erased identity
records silently to make Restore appear successful.

## Release sequence and required evidence

| Stage | Exit evidence | Current gate |
|---|---|---|
| Source integration | Real HTTP/Postgres policy tests, simulator native tests and inspected UI states | Checked per CI; no real purchases |
| Private pilot | New API healthy, unauthorized requests refused, resource caps preserved; no unrelated services changed | Dedicated VM; public DNS/TLS absent |
| Identity/device | Valid HTTPS; signed iPhone Apple nonce login, expiry, logout and erasure; no credentials in shared caches | Apple Team/provisioning and owner DNS |
| Provider collection | Actual owned CLI slots; fresh/null/error/stale readings, offline collector and independent account mapping | Real accounts not exercised |
| StoreKit sandbox | Buy/cancel/Ask to Buy/restore/reinstall, failed delivery retry, renewal/refund/revocation, newer update during delivery, account switch, ownership conflict and deleted-account recreation | App Store products, roots, sandbox configuration and recovery policy |
| Small surfaces | Real Home/Today/Lock widgets and paired Watch, cache deletion/offline/stale and large text | Physical-device run |
| Release operations | User-data backup/restore, deletion/retention, privacy/EULA reachable over HTTPS, independent security review and load budget | Not production-ready |

App Store/TestFlight publication, paid Apple enrollment and merges require
separate authorization. Do not open sales merely because a compiler or dependency
audit is green. Keep existing GitHub release-gate issues open until verified.
