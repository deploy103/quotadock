# Scoped cloud collector

Run Node 22+ with CodexBar installed and authenticated **locally**:

The cloud collector requires POSIX user IDs and private file permissions
(macOS/Linux). Windows credential-file/ACL support is not implemented; do not
disable the ownership checks to make it run. Live provider availability still
depends on the installed CodexBar build and its supported credential sources.

```sh
node bridge/cloud.mjs pair https://YOUR-TRUSTED-QUOTADOCK-SERVER
node bridge/cloud.mjs run
# Or process at most one lease:
node bridge/cloud.mjs once
```

Use your deployment's trusted HTTPS origin (no path, credentials, or query).
TLS verification remains enabled and redirects are never followed. Enter the
printed eight-character code on the phone and explicitly confirm selected slots.
The CLI never accepts Apple sessions or provider credentials. Its scoped grant
is stored exclusively in `~/.config/quotadock-cloud/collector.json` (0600 in
a private 0700 directory). Do not copy it into issues, logs or source control.
Revoke in the phone's collector list; remove the local file before re-pairing.
Grants expire after 30 days and are not silently renewed.

One unbound slot per provider uses CodexBar's current local login. For independent
Claude, Codex and Grok slots, use a recent CodexBar with `--all-accounts` and
`cacheAccountKey` JSON support. Older versions fail closed: they never substitute
the active account. Gemini remains one slot because its CLI has no independent
account selector. Registering more slots does not create upstream eligibility.

```sh
# These commands query locally configured accounts, contacting provider APIs.
node bridge/cloud.mjs accounts codex oauth
node bridge/cloud.mjs accounts claude oauth
# Cookie accounts on a supported Mac use web, not oauth:
node bridge/cloud.mjs accounts grok web
# Copy the exact slot UUID on the phone; bind to a locally confirmed fingerprint.
node bridge/cloud.mjs map PHONE_SLOT_UUID codex LOCAL_FINGERPRINT oauth
```

Configure CodexBar's independent credentials/profiles first. Confirm which
account each opaque fingerprint represents locally before binding; the collector
cannot prove that two upstream logins have different quota owners. Account labels,
array positions and raw credentials are not accepted selectors. Fingerprints hash
CodexBar's durable account key, which may contain an email/workspace identifier;
only those hashes and slot bindings go into local `accounts.json` (0600).
They are never included in server observations. Do not share that file.

Every duplicate-provider slot in a grant requires a distinct explicit mapping.
Sources are pinned to oauth/web; Codex accepts oauth only. Missing or duplicate
keys produce unavailable readings, never another account's data. Mapping writes
are atomic; stop the worker while configuring and restart afterward. Changing
credentials may change a key and require re-confirmation. Re-pairing requires
removing old `accounts.json` as well as the old grant, after revocation.

A grant/batch has at most 50 slots. The phone selects a batch; initial selection
is the first 50 server-listed slots. An active Live session retains its server's
selection until stopped. Pro registration is uncapped, not an unbounded request.
CodexBar `--all-accounts` may query unselected locally configured accounts within
that provider/source group; only explicitly selected matches are uploaded.
Verify this cost and provider policies before enabling frequent Live collection.
Only sanitized observations are sent, never identities, diagnostics, credentials
or raw command output. Multi-account behavior is fixture-tested, not yet verified
with real independently authenticated provider accounts.

Collection is uncached, waits past the job's whole-second issue boundary, and
preserves CodexBar's source timestamp. Missing timestamps/data, stale source
results and provider failures cannot debit quota. Offline or timed-out leases
expire without debit. Temporary network errors back off; revoked grants stop
the process. In `run` mode, job polling targets 20-second spacing. Automatic
due checks target 20-minute spacing; the server enforces the tier's actual
120/60/20–120-minute interval. Disable local automatic updates in cloud settings
for manual-only collection. This continues while the computer is online even
after the phone session expires; it is not iOS background polling. Run only one
worker per grant/installation to avoid duplicate upstream calls. No demo/fabricated
observations are used.
