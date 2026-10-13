# Scoped cloud collector

Run Node 22+ with CodexBar installed and authenticated **locally**:

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

This first collector supports **one slot per provider**. Duplicate-provider
grants/jobs are rejected, not mapped to the same active credentials. CodexBar
uses its current local login/profile; verify the phone slots match those logins.
Independent profiles are not implemented. Only sanitized observations are sent,
never identities, diagnostics, provider tokens or raw command output.

Collection is uncached, waits past the job's whole-second issue boundary, and
preserves CodexBar's source timestamp. Missing timestamps/data, stale source
results and provider failures cannot debit quota. Offline or timed-out leases
expire without debit. Temporary network errors back off; revoked grants stop
the process. Run only one worker per grant/installation to avoid duplicate
upstream calls. No demo/fabricated observations are used.
