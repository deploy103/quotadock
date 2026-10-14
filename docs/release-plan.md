# Release plan and failure contracts

Source-preview plan, 2026-10-14. Implemented code is not a signed release or proof
of Apple purchases, provider access, public HTTPS or physical-device behavior.
Release gates remain open until their real-stack scenarios below pass.

The 12:00 KST gate has passed. [Post-noon application CI](https://github.com/quotadock-dev/quotadock/actions/runs/38506753875)
passed 73 native tests and iPhone/Watch/WidgetKit builds, 30 Node 22 tests and
10 imported skill tests; the root-only service test also passed separately.
Private-backend CI passed 127 HTTP/cryptography/disposable PostgreSQL tests.
Real local TLS and disposable Compose probes reproduced and fixed certificate
validation, long-fraction timestamp and proxy address-allocation defects.
Six affected/demo states were inspected. These results validate source contracts,
not real Apple/provider/device flows or activation of the new server source.

## Account and data boundaries

The phone owns its Apple-derived opaque access/refresh credentials in device-only
Keychain. Access lasts at most one hour, within a fixed absolute 30-day login
family. Foreground operations coalesce renewal before the access deadline;
rotation never extends the family. The original renewal UUID, start time and
two-send reservation survive restart. A same-key retry can recover only the
immediate unused child within the server's 60-second window; spent-token replay
outside that contract revokes the family and its access credentials. There is
no automatic replay of a rejected mutation. Legacy access-only sessions still
require sign-in on expiry. Logout uses the refresh credential to revoke the
captured family even if access expired; erasure cascades all families. These
are validated simulator/disposable-server contracts, not proof of persistent device login.
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
   Transient uncertainty retries the same serialized body/key, at most two sends
   within one 60-second operation. Continuing an unchanged batch first resolves
   `/v2/jobs/request/:key`; known jobs are polled, not reposted. A definitive
   rejection clears the intent. Auto/force commands are saved before sending in
   the phone-only device-bound Keychain; unknown outcomes survive process restart
   only within the same login family, including normal bearer rotation; legacy
   records remain bound to their exact access credential. The saved command contains
   selected UUIDs, mode, original key and exact body, not a bearer token. Recovery
   rechecks owned slots after a successful server read and then resolves that
   key. Inaccessible, malformed or no-longer-owned saved commands block refresh
   sends, not validated server reads; a later read retries recovery without
   deleting the unresolved record. Explicit clear/sign-out resets that state.
   Foreground auto-refresh continues an unresolved forced command instead
   of issuing a different key. Logout, account switch, selection change after
   successful recovery and terminal completion discard it. Live commands remain memory-only; resuming
   Live after restart still requires explicit opt-in and server session state.
2. Poll the returned job ID every five seconds, for at most 60 seconds in the
   foreground. Each lookup rechecks the session and tenant under the owner lock.
3. `cached` means no due collection; `expired` means the lease ended. `completed`
   includes failed/stale collection, **not necessarily fresh quota**.
4. After a terminal result, perform one authoritative owned snapshot traversal
   and derive the slot list from those same rows. It reads at most 20 pages of
   250 rows/5,000 slots, 8 MiB and 60 seconds, spacing request starts by at least
   500 ms without weakening server limits. Legacy first-page 404 fallback also
   validates against an owned account list. Preserve last usable data on failure.
5. Background, lock, logout and account switch cancel waiting. A polling timeout
   does not cancel the server job, fabricate quota or spend a credit. An explicit
   retry of the unchanged batch resolves/resumes that same intent. The collector
   can still complete the five-minute lease; a later read sees it.

An old backend without job lookup makes waiting unavailable, not successful.
Deploy the status endpoint and 250-row page support before this client; an old
50-row-only page route returns 400, not the legacy-fallback 404. New quota date
strings are bounded to 64 ASCII bytes, without changing their original value;
legacy oversized records need inspection before rollout, not invented timestamps.
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
   The server verifies Apple signatures, app/environment, ownership and replay,
   then queries current App Store state for that exact original chain/group and
   verifies the returned transaction/renewal. Historical validity alone is not
   a paid grant. Missing current-state configuration disables purchases; upstream
   failure leaves verification unconfirmed, rather than trusting an old receipt.
5. Finish only after a valid accepted server response. A server `free` response
   also acknowledges an expired/refunded transaction but grants no paid tier.
   Re-read only `/v2/me`; the purchase model never assigns Plus/Pro itself.
   Receipt delivery does not traverse quota pages or rewrite quota caches and
   selection. A concurrent quota read coalesces pending entitlement reads into
   one follow-up, scoped to the same session revision and foreground authority.
   Live preflight also reads metadata only; terminal jobs still reload quota
   pages. It waits while another request/read owns the model instead of treating
   a skipped send as an unconfirmed collection.
6. Keep the update listener for app lifetime. Recover unfinished transactions and
   current entitlements once on a new configured session. Explicit Restore alone
   calls `AppStore.sync`; ordinary quota reads do not repeatedly upload receipts.
7. Deduplicate the same in-flight transaction, but retain newer signed updates
   (including refund/revocation) for another pass. Logout/server/session/account
   changes invalidate completions and clear queued receipts/products.
   A 401 during receipt delivery also invalidates cloud authority, stops Live
   and requests sign-in again; it never finishes the unconfirmed transaction.
8. Network/server failure leaves delivery unconfirmed for reconnect/Restore;
   new unfinished transactions are not finished. Different-cloud-account purchases
   are refused, not silently transferred. Account erasure does not cancel Apple's subscription; link to
   Apple's subscription management and explain this before purchase/erasure.

Account erasure followed by a new cloud registration creates a new UUID. The
current implementation consequently refuses an old subscription's account token,
even for the same Apple sign-in. Define and validate an authenticated recovery
policy before opening sales; never bypass ownership or retain erased identity
records silently to make Restore appear successful.

The editable cloud URL also selects the issuer of `appAccountToken` and the
receipt-delivery destination. HTTPS alone does not establish that a custom
operator can honor the publisher's App Store products. Recommended release
policy: purchases for these product IDs use only the official hosted origin;
custom bridge origins and development cloud endpoints remain separate. This
restriction is a proposal, not implemented behavior. Decide and test the origin
policy before enabling sales, including existing sessions saved for another URL.

A client-only signed ownership/count proof cannot preserve Live spending across
repeated erasure: an older valid proof can replay a lower count. One proposal is
an explicitly disclosed, bounded HMAC purchase-period/day ledger retained after
erasure, combined with authenticated ownership recovery. That changes the deletion
promise and requires privacy/product approval before implementation. It also
needs a defined proof-loss/reinstall path, recovered notification ownership and
the existing per-user Pro-day semantics across multiple purchase chains. No such
ledger or erased-account recovery is implemented; sales stay closed.

## Credential and cache failures

Before presenting Apple authorization, the client rejects a challenge unless it
has exactly the three documented fields, a canonical UUID, a 43-byte base64url
nonce and the server's 300-second lifetime. A response arriving after background,
lock or cancellation cannot start the Apple dialog. These source guards need
native tests; they do not replace server nonce consumption or signature checks.

Cloud 401, an expired login family or an expired legacy session clears device-only
authority and invalidates in-flight completions without deleting usable quota
observations. Access expiry within a valid family first permits foreground
renewal. Inaccessible or failed Keychain replacement never deletes an old usable
credential first. A failed/old/exhausted pending renewal remains saved and blocks
new authorization sends until explicit sign-out/reconnection; no new key is
issued with a possibly spent parent. Parsed fresh grants that cannot be saved
or lose foreground authority are revoked best-effort; completely lost auth
responses can leave unconfirmed server families until their fixed deadline.
Quota reads track their own revision so a superseded metadata response cannot
release a replacement account's read ownership or publish another owner's data.
While login or remote erasure is busy, the form freezes the selected server and
consents. Erasure clears local authority first and displays pending confirmation;
it does not declare server deletion successful before the bounded response.
Bridge 401/403 have fixed reconnect/access-policy
messages, without displaying server bodies or diagnostics. HTTPS bridge fetches
reject redirects and cookies, have a 20-second absolute deadline and a 256 KiB
stream limit, including silent or trickling bodies. Pairing URLs are limited to
2,048 UTF-8 bytes and the encoded Keychain item to 8 KiB on both save and load;
oversized or insecure stored pairings do not start a request.

The phone's Watch outbox keeps only the latest sanitized intention. Activation
reconciles from authoritative phone disk: an absent cache queues an empty,
non-demo snapshot even after process restart. A clear arriving before activation
must not silently leave old quota on Watch. WCSession acceptance is not delivery
confirmation; offline devices can retain previously rendered content until the
OS delivers the new snapshot. Widgets only read sanitized local cache.

## Recovery must not reopen obsolete authority

A database backup can predate logout, refresh rotation, refund or account erasure.
Restoring it can consequently revive a spent credential, an erased account or a
previously paid entitlement. An empty-database restore proves none of those
boundaries. Keep restored user data isolated from public traffic until the recovery
procedure invalidates restored access/families, collector grants, pairings and
challenges, reconciles current subscription state, and accounts for erasures made
after the backup. Force phone sign-in and collector re-pairing; keep the stable
pseudonym key, rather than rotating it to simulate credential invalidation.

The erasure reconciliation source, backup/offsite retention and recovery objective
still need a disclosed policy and tested procedure. Do not silently introduce a
retained erasure journal. A restored instance must stay closed if that evidence
is unavailable. This is a release gate, not an implemented recovery automation;
shared-database restore or invalidation requires separate operator approval.

## Release sequence and required evidence

| Stage | Exit evidence | Current gate |
|---|---|---|
| Source integration | Real HTTP/Postgres policy tests, simulator native tests and inspected UI states | Post-noon checks above passed; physical-device/provider/Apple behavior remains open |
| Private pilot | New API healthy, unauthorized requests refused, resource caps preserved; no unrelated services changed | Dedicated VM runs the prior pilot; new source/schema not activated, public DNS/TLS absent |
| Identity/device | Valid HTTPS; signed iPhone nonce login, rotation/restart/replay, family expiry, logout and erasure; no credentials in shared caches | Apple Team/provisioning and owner DNS |
| Provider collection | Actual owned CLI slots; fresh/null/error/stale readings, offline collector and independent account mapping | Real accounts not exercised |
| StoreKit sandbox | Buy/cancel/Ask to Buy/restore/reinstall, failed delivery retry, renewal/refund/revocation, newer update during delivery, account switch, ownership conflict and deleted-account recreation | App Store products, roots, sandbox configuration and recovery policy |
| Small surfaces | Real Home/Today/Lock widgets and paired Watch, cache deletion/offline/stale and large text | Physical-device run |
| Release operations | User-data backup/restore, deletion/retention, privacy/EULA reachable over HTTPS, independent security review and load budget | Not production-ready |

App Store/TestFlight publication, paid Apple enrollment and merges require
separate authorization. Do not open sales merely because a compiler or dependency
audit is green. Keep existing GitHub release-gate issues open until verified.
