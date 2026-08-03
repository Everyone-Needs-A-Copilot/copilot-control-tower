# Connecting a machine to the organization's shared credential store

This is the runbook for getting one more Mac able to read the organization's shared secrets (an Infisical store) — today's manual, app-less path, and the `cc connect` path that replaces it. It is written for whoever is doing the connecting: an org admin acting for someone else, or a technical user acting for themselves. It is not written for the non-technical end user directly — that experience is the still-open design fork WP-396/WP-398 (`docs/03-design/connect-experience-walkthrough.md`) describe; this document is the mechanism underneath whichever surface eventually reaches that user.

## How it works

The `copilot`/`cc` CLI resolves every credential a service declares (`requires_secret: <NAME>`) through a fixed, fail-closed ladder, in order: the shared managed store itself, the per-user OS keychain, an interactive device-code sign-in (not implemented yet), and a one-time secure paste (interactive terminals only). A miss at every rung is a hard failure, never a silent empty value — see `cli-copilot`'s `copilot_cli/config/secrets_ladder.py` for the authoritative implementation.

The keychain rung reads from one fixed macOS Keychain service, `copilot-cli`, using the credential's own NAME as the account. For example, the two credentials that authenticate a machine to the shared store itself — `INFISICAL_CLIENT_ID` and `INFISICAL_CLIENT_SECRET` — live at service `copilot-cli`, accounts `INFISICAL_CLIENT_ID` and `INFISICAL_CLIENT_SECRET` respectively. "Connecting a machine to the store" is nothing more than getting those two values into that keychain location — everything downstream (the ladder, `cc connections --json`'s presence check, every service that in turn reads secrets out of the store once authenticated) already knows how to find them there.

**Why never `.env`.** An earlier generation of the docs told people to put `INFISICAL_CLIENT_ID`/`INFISICAL_CLIENT_SECRET` in a tier's `.env` file. That was always the wrong rung for a bootstrap credential — the store cannot hold the credentials used to authenticate to itself (a bootstrap paradox), and a `.env` file living in a git-tracked layer is exactly the kind of "secret in inheritance content" this ecosystem's invariants forbid (`copilot-control-tower/CLAUDE.md` invariant #6: "secrets never enter inheritance content or any git repo"). `cli-copilot`'s own `config/managed_store.py` enforces this store-side (`_NEVER_FROM_STORE`), and `cc connections --json`'s presence check now enforces it defensively too (WP-395 gap G-1) — these bootstrap names are always checked against the keychain, never the store, regardless of what a tier's overlay declares. The keychain is the only place they are ever meant to live on a machine.

## RD-1 — the rule this runbook has to honor

> Use a scoped, revocable per-machine identity; do not distribute the org-wide `ecosystem-admin` credential.

This is a ratified decision (`docs/40-initiatives/02-enac-self-onboarding/phases/phase-6-ecosystem-install-and-onboarding-proof.md` §7, RD-1), and it is the one rule that matters most in this whole runbook. **Every machine gets its own Infisical machine identity, minted for that machine alone, scoped to read-only access at the org's shared path.** No two machines should ever share one identity, and the identity that has admin/write access to the org's Infisical project (the one used to set the whole thing up) must never be the one handed to an individual machine. Neither `cc connect` nor the manual `security` commands below know or care where a value came from — they are credential-agnostic, and will happily write whatever they are given. RD-1 is not something the tooling enforces for you; it is a discipline the admin minting the identity has to hold.

There is no automated per-machine identity-provisioning verb today (`copilot infisical identity` exposes only `list`/`create`, and `create` alone mints a bare identity with no Universal Auth method, client secret, project membership, or role attached — see WP-395's gap G-5). Minting a scoped identity is a manual step in the Infisical dashboard, done by an org admin, every time.

## Doing it today, without the app (the manual path)

This is the mechanically correct action for any Mac, today, whether or not Control Tower or `cc connect` is installed.

### Step 1 — an org admin mints a per-machine identity in the Infisical dashboard

At the org's Infisical endpoint (for Everyone Needs A Copilot, that's `https://secrets.ineedacopilot.com` — check `~/.claude/ecosystem.yml`'s `store.endpoint` for any other org):

1. Sign in to the dashboard with an account that has admin access to the org's project.
2. Create a new **Machine Identity**, named for the machine or the person it's for (e.g. `bob-laptop`, not a generic name — the whole point of a per-machine identity is being able to tell them apart later and revoke exactly one).
3. Attach a **Universal Auth** authentication method to that identity. This generates a Client ID and a Client Secret — this is the one and only moment the Client Secret is shown; copy it somewhere temporary and safe, because Infisical will not show it again.
4. Add the identity to the org's project (`workspace_id` in `ecosystem.yml`'s `store:` block) with **read-only** access at the shared environment/path (for Everyone Needs A Copilot, `prod:/shared`). Do not grant write access to a machine identity that only needs to read.
5. Hand the Client ID and Client Secret to whoever is setting up the machine, over whatever channel your org treats as appropriate for a short-lived secret (never a channel that leaves a permanent, searchable record — e.g. not a public Slack channel history).

### Step 2 — on the machine itself, write the two values into the keychain

The person setting up the machine (who may be the same admin, or may be the machine's own user, handed the values from step 1) runs, in a real Terminal:

```sh
security add-generic-password -a INFISICAL_CLIENT_ID -s copilot-cli -w '<the Client ID from step 1>' -U
security add-generic-password -a INFISICAL_CLIENT_SECRET -s copilot-cli -w '<the Client Secret from step 1>' -U
```

`-a` is the account (the credential NAME), `-s` is the service (always the fixed `copilot-cli`), `-w` is the value, and `-U` tells the Keychain to update the entry if one already exists rather than erroring. Two caveats worth knowing about this manual form specifically (neither applies to `cc connect`, below): the value after `-w` is briefly visible to anything else on the machine that can list running processes (`ps`) while the command runs, and it is likely to be saved in your shell's history file unless you take care to avoid that (many shells skip history for a line that starts with a leading space — check yours). For a one-off setup on a machine you trust, this is an accepted, narrow window; it is exactly the leak class `cc connect` was built to close for the general case.

### Step 3 — verify

```sh
cc connections --json
```

Find the `infisical` row in the `connections` array (or pipe through `jq` / the non-JSON `cc connections` rendering, which groups rows into "Ready to use" and "Available to connect"). It should now read `"secret_state": "ready"` with `"missing": []`. If it still reads `needs-connect`, double-check the account names are exactly `INFISICAL_CLIENT_ID` and `INFISICAL_CLIENT_SECRET` (case-sensitive) and the service is exactly `copilot-cli`, and that `security find-generic-password -a INFISICAL_CLIENT_ID -s copilot-cli` (no `-w`) reports the item found at all.

A `needs-connect` read from a headless, detached, or locked-keychain session is a probe artifact, not proof the identity is dead — re-check from an interactive session per `CLAUDE.md`'s Credentials doctrine before re-minting anything; a genuinely dead identity shows up instead as a rejection the store itself logs server-side (e.g. a 401 for this machine identity in Infisical's own audit log even though the local keychain read succeeds), and only that evidence means starting over at Step 1 above to mint a replacement.

## Doing the same thing through the app (`cc connect`)

Once `cc` 2.3.0 or later is installed, the same two writes happen through one verb instead of two raw `security` invocations, and without the `ps`/shell-history exposure the manual path carries:

```sh
echo '{"INFISICAL_CLIENT_ID": "<client id>", "INFISICAL_CLIENT_SECRET": "<client secret>"}' | cc connect infisical --json
```

The values travel on **stdin only** — never as a command-line argument, never as an environment variable, never written to a file. `cc connect` reads the service's currently-missing credential NAMES from the same machinery `cc connections --json` already uses, writes each supplied value to the keychain via a non-leaking `security -i` batch invocation (the value never appears in `ps` output for this call either), then re-checks and returns the fresh row plus a per-credential outcome (`stored`, `already-present`, or `failed` — never a value, in the request or the response). This is the mechanism the in-app Connect surface calls. That surface now exists: a `Connect…` button on any row the CLI reports as `needs-connect`, in both the wizard's step 6 and the Settings "Your connections" card, opening a native secure-input sheet that passes what you type to this verb over stdin and never displays, stores, or logs it. A row the CLI reports as `no-store` deliberately gets no button — nothing about it was verified, so it is rendered as a fact rather than an action. Neither the verb nor the sheet decides who is allowed to receive a value: that responsibility still sits with whoever mints the identity in step 1 above, per RD-1.

To re-check a service's row without writing anything (no stdin read, nothing changes) — the same call the app makes right after a successful connect, to refresh what it shows:

```sh
cc connect infisical --check --json
```

### Verification is the same either way

```sh
cc connections --json
```

`infisical` (or whichever service you connected) should read `"secret_state": "ready"`.

## What this runbook does not cover

- **Minting the identity is still a manual, human step.** There is no automated "provision a new machine identity" verb yet (WP-395 gap G-5); an admin does step 1 above by hand, every time, in the Infisical dashboard.
- **There is no delivery mechanism from the store to a machine's keychain yet.** Getting the Client ID/Secret from the admin who minted them to the person setting up the machine is, today, an out-of-band human hand-off (WP-395 gap G-6) — this runbook does not prescribe a channel beyond "don't use one that leaves the secret in a permanent, searchable record."
- **The non-technical end-user experience is designed but not built.** `docs/03-design/connect-experience-walkthrough.md` (WP-396) and its rendered walkthrough (WP-398) laid out two candidate futures — a "membership is access" model where a person never sees a credential moment at all, versus a "claim code" approval flow. The owner then ratified a third framing on 2026-08-02: self-service provisioning verified by the GitHub membership a person already holds, designed in [`../05-security/self-service-store-provisioning.md`](../05-security/self-service-store-provisioning.md) (WP-399), threat-modelled twice (WP-400/WP-401), and rendered as [walkthrough 18](../40-initiatives/02-enac-self-onboarding/walkthroughs/18-self-service-provisioning-uxd-walkthrough.html). It is at review, not ratified, and none of it is built. **Everything this runbook describes is the bridge that design deletes** — see walkthrough 18 screen 13 for why both exist at once.
