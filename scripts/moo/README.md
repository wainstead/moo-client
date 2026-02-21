# Local LambdaMOO (Docker)

This stack runs LambdaMOO only (proxy stays separate/local).

## Image choice

Uses `wiredwizard/lambdamoo:1.8.3` from Docker Hub.

## Quick start

From repo root:

1. Optional: copy env defaults and customize test credentials.

```bash
cp .env.moo.example .env.moo
```

2. Start MOO container (binds host `127.0.0.1:7777`).

```bash
./scripts/run_local_moo.sh up
```

3. Run first-time scripted bootstrap (idempotent marker in persisted volume).

```bash
./scripts/run_local_moo.sh bootstrap
```

4. Tail server logs.

```bash
./scripts/run_local_moo.sh logs
```

## What bootstrap does

- logs in as wizard
- sets wizard password
- creates one regular user and password
- creates two rooms

Credentials/room names are controlled by `.env.moo` (or compose defaults).

## Persistence

The compose stack uses named volume `moo_data`.

- Stop without deleting data:

```bash
./scripts/run_local_moo.sh down
```

- Stop and delete DB/state:

```bash
./scripts/run_local_moo.sh reset
```
