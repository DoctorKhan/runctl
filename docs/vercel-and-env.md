# Environment variables, shared values, and Vercel

Vercel’s dashboard stores **flat** name → value pairs per environment. It does **not** offer “alias this key to that key” or `${VAR}` interpolation in the UI. If three keys must hold the same URL, you either **duplicate the value** in the dashboard or **manage one source of truth** outside Vercel and sync.

Below is a practical split: **local + CI** use a manifest; **Vercel** uses duplication or a secrets sync product.

## 1. Single source of truth in the repo (recommended baseline)

Keep a **manifest** (not loaded directly by Next/Vite) that lists each real value once and expresses aliases with `${…}`:

- Example: [`examples/env.manifest.example`](../examples/env.manifest.example)
- Expand to a generated file that frameworks **do** load:

```bash
pnpm exec runctl env expand env.manifest --out .env.local
# or: node node_modules/@zendero/runctl/scripts/expand-env-manifest.mjs env.manifest --out .env.local
```

Add **`.env.local`** (and optionally `.env.manifest` if it contains no secrets—usually it *does*, so keep the manifest **gitignored** or use a **`.env.manifest.example`** without real values).

**Workflow**

1. Edit `env.manifest` (gitignored) with real secrets.
2. Regenerate `.env.local` before dev: same command as above.
3. Commit only **`env.manifest.example`** (no secrets) so others know which keys exist.

For **multiple keys, same value**, define one canonical key (`APP_ORIGIN`) and set:

```text
NEXT_PUBLIC_APP_URL=${APP_ORIGIN}
VITE_PUBLIC_APP_URL=${APP_ORIGIN}
```

## 2. Vercel: pulling remote env into local files

To align local dev with what is already on Vercel:

```bash
vercel env pull .env.vercel.local
```

Merge strategy (typical):

- **Generated** `.env.local` from your manifest for **shared-value consistency**.
- **Vercel-only** keys (e.g. `VERCEL_*`, analytics tokens) via `vercel env pull` into `.env.vercel.local` and load **both** (Next loads multiple `.env*` in priority order—see Next docs).

If the same logical value must exist under two names **on Vercel**, the dashboard still needs **two entries** with the same string unless you use option 3 or 4.

## 3. Pushing manifest-derived values to Vercel (scripted duplication)

There is still **no native “link”** between keys on Vercel. A script can read the **expanded** map once and run the CLI for each name:

```bash
# Example pattern (run from app linked to Vercel):
set -a && source .env.local && set +a
echo -n "$NEXT_PUBLIC_APP_URL" | vercel env add NEXT_PUBLIC_APP_URL production
echo -n "$VITE_PUBLIC_APP_URL" | vercel env add VITE_PUBLIC_APP_URL production
```

Use a **non-interactive token** (`VERCEL_TOKEN`) in CI only; avoid committing tokens. Prefer **Preview** vs **Production** environments explicitly.

This is **intentional duplication in the cloud**, but **one edit** locally (manifest → expand → script loop).

## 4. External secret managers (teams)

If many projects and environments need DRY + audit:

- **Doppler**, **Infisical**, **1Password Secrets Automation**, etc. can sync to Vercel and inject the **same** secret into multiple Vercel variable names (product-specific feature).

Use this when shell scripts are not enough.

## 5. Reduce duplication in *code*

Sometimes two env vars exist for historical reasons. If both client and server can read the **same** name (e.g. only `NEXT_PUBLIC_*` where acceptable), prefer **one** variable in Vercel and one line in the manifest.

## 6. Relation to Runctl’s `.run/ports.env`

[`.run/ports.env`](../README.md) is for **dev server `PORT` / `HOST`**, not for Vercel deployment. Keep deployment secrets in `.env.local` / Vercel / a manifest as above.

## Summary

| Goal | Approach |
|------|-----------|
| Same value, many names **locally** | `env.manifest` + `expand-env-manifest.mjs` → `.env.local` |
| Match Vercel → laptop | `vercel env pull` + merge with generated `.env.local` |
| Same value, many names **on Vercel** | Duplicate in UI, or scripted `vercel env add`, or a secrets manager with Vercel sync |
