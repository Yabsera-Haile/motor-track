# Motor Track

An internal app for tracking rent payments from the company's motorbikes. It reads M-Money SMS to mark payments, alerts the team when a driver is late or short, and reports collections and bank deposits.

- Plan, business rules and setup steps: [docs/PLAN.md](docs/PLAN.md)
- Design: https://claude.ai/artifact/PEktzKYUAXMrMwohX21cHK

## Layout

| Path | What |
|---|---|
| `app/` | Flutter app (Android first, iOS later) |
| `supabase/migrations/` | Database: tables, oldest-debt-first allocation, dues, alerts, security |
| `supabase/tests/database/` | Business-rule tests (pgTAP) |
| `supabase/functions/push/` | Edge Function that sends notifications through Firebase |
| `supabase/seed.sql` | Sample data for local development only |

## Run it locally

Needs Docker Desktop, Node and Flutter.

```bash
npx supabase@3.0.0 start -x studio,imgproxy,storage-api,logflare,vector,mailpit,supavisor,postgres-meta,edge-runtime
```

```bash
npx supabase@3.0.0 db reset
```

That loads the sample bikes from the design. The local team code is `local-dev-code`.

```bash
cd app && flutter run --dart-define-from-file=env/local.json
```

`env/local.json` points at the local backend. Copy `env/example.json` to `env/prod.json` for the real project.

## Tests

```bash
npx supabase@3.0.0 test db
```

```bash
cd app && flutter test
```

## Deploy the backend (once the Supabase project exists)

1. `npx supabase@3.0.0 login` (opens the browser)
2. `npx supabase@3.0.0 link --project-ref <project-ref>`
3. `npx supabase@3.0.0 db push`
4. In the Supabase SQL editor, set the team code: `select private.set_team_code('your team code');`
5. Push notifications (after Firebase is set up). Run these from the repo root with your own values:
   - `npx supabase@3.0.0 secrets set PUSH_SECRET=<long random string>`
   - `npx supabase@3.0.0 secrets set FCM_SERVICE_ACCOUNT="$(cat path/to/service-account.json)"`
   - `npx supabase@3.0.0 functions deploy push`
   - In the SQL editor, store the function URL and the same secret in Vault:
     `select vault.create_secret('https://<project-ref>.supabase.co/functions/v1/push', 'push_function_url');`
     `select vault.create_secret('<same long random string>', 'push_secret');`
