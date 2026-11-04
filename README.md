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

## Build the Android app

These files stay on the build PC and are not in git. Keep a backup of the first two: every update must be signed with the same key.

| File | What |
|---|---|
| `app/android/key.properties` | Signing key password |
| `app/android/app/upload-keystore.jks` | Signing key |
| `app/android/app/google-services.json` | Firebase config (download again from the Firebase console if lost) |
| `app/env/prod.json` | Supabase URL and publishable key |

```bash
cd app && flutter build apk --release --split-per-abi --dart-define-from-file=env/prod.json
```

Hand out `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` (most phones), or `app-armeabi-v7a-release.apk` for older 32-bit phones. Raise `version:` in `pubspec.yaml` for every release.

Before handing an APK out, check it contains the app code: `lib/arm64-v8a/libapp.so` (about 6.5 MB) must be inside the file. An APK without it installs fine but closes as soon as it opens. That happened once after the build folder moved: Flutter's cache in `app/.dart_tool/flutter_build` still thought the code was compiled. Deleting that folder and building again fixes it.

`app/build` is a junction to `%LOCALAPPDATA%\MotorTrackBuild\app-build`, so OneDrive doesn't lock build files mid-build.

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
5. Push notifications (done for the live project on 4 Nov 2026). CLI 3.0 asks before changing the live project; `--yes` confirms.
   - `npx supabase@3.0.0 functions deploy push --use-api --no-verify-jwt`
   - Function secrets, from a temporary `.env` file you delete straight after (on Windows the shell mangles JSON passed on the command line):
     `PUSH_SECRET=<long random string>` and `FCM_SERVICE_ACCOUNT='<the Firebase service-account JSON on one line>'`, then
     `npx supabase@3.0.0 secrets set --env-file <that file>`
   - In the SQL editor, store the function URL and the same secret in Vault:
     `select vault.create_secret('https://<project-ref>.supabase.co/functions/v1/push', 'push_function_url');`
     `select vault.create_secret('<same long random string>', 'push_secret');`
   - Check with Settings → Test notification in the app. It reaches every phone that has opened 0.4.0 or later.

   To change the push secret, repeat the last two steps with a new value. The old one stops working.
