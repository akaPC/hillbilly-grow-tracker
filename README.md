# Hillbilly Monotub Grow Tracker

A single-file, dark-tactical web app for tracking three Hillbilly cubensis monotubs end-to-end — colonization through reflush — with cross-device sync via Supabase.

**Live demo:** https://akapc.github.io/hillbilly-grow-tracker/

No build step. One `index.html`. Open it in a browser. State syncs through Supabase Realtime so the dashboard stays current across phone, tablet, and desktop.

---

## Features

- **Dashboard** — three live tub status cards, master phase timeline, running totals (flushes / wet / dry / contam), and active alerts driven by phase + age heuristics.
- **Tub Management** — per-tub detail with phase tracker, advance/back buttons, observations log, photo uploads to Supabase Storage, flush history with moisture-loss calc, and an Inkbird settings reference card (TS=77F, HD=1F, CD=1F, AH=85F, AL=70F).
- **Phase Guide** — six collapsible phases with step-by-step instructions, sandwich tek diagram (1 lb bottom buffer / mixed middle / 1 lb top cap), inventory snapshot (3 grain bags · 8 Boomr Bags · Myco Coco · 2 reserve), Boomr Bin automation hookup diagram (FAE Fan · Myco-Mister · Mycontroller probe), and a fruiting conditions card (74–76°F, 90–95% RH, 12 hr light).
- **Harvest Log** — log per-flush wet & dry weights and notes, auto-calculated moisture loss %, running totals per tub, and a yield bar chart per flush across all tubs.
- **Contamination Checker** — quick color reference (green/black/pink = bad, white/blue bruising = normal), 4-question decision tree (isolate vs continue vs terminate vs spot-treat), and a photo-backed event log.
- **Calendar View** — visual 6-phase timeline per tub with current-position marker and projected pin / harvest / reflush dates based on each tub's spawn-to-bulk date.
- **Real-time sync** — Supabase Realtime subscriptions on all five tables; another device's update reflects on yours instantly.
- **Offline support** — writes queue to `localStorage` when offline and flush automatically on reconnect; optimistic UI with rollback on error.
- **Sign-in required** — nothing loads until you sign in; only emails you allow-list can read or write.
- **Photos** — uploaded to a private Supabase Storage bucket (`grow-photos`) and shown through short-lived signed links.

---

## Setup

### 1. Create or reuse a Supabase project

1. Go to <https://supabase.com> and create a project (or use an existing one).
2. Wait for it to provision.

### 2. Run the schema

1. Open the project's **SQL Editor** → **New query**.
2. Paste the entire contents of [`schema.sql`](./schema.sql) and **Run**.
3. The script is idempotent — safe to re-run if you make changes.

`schema.sql` provisions:

- five tables: `tubs`, `phase_log`, `observations`, `harvests`, `contamination_events`
- a `touch_updated_at` trigger on `tubs`
- an `allowed_emails` table and an `is_allowed()` check
- **RLS enabled** on every table, with one policy per table that grants access only to signed-in users whose email is in `allowed_emails`
- the `supabase_realtime` publication, with all five tables added so Realtime broadcasts changes
- a **private** `grow-photos` Storage bucket with the same allow-list policy
- a seed insert of three tub rows so the dashboard renders on first load

### 3. Create your login

1. **Authentication → Users → Add user**: enter your email and a password.
2. **SQL Editor**: allow that email (run once per person you want to give access):

   ```sql
   insert into public.allowed_emails values ('you@example.com');
   ```

3. **Authentication → Sign In / Providers**: turn off **Allow new users to sign up**.

### 4. Wire credentials into `index.html`

1. In Supabase: **Project Settings → API** → copy the **Project URL** and **anon public** key.
2. Open `index.html` and edit the constants near the top of the `<script>` block:

   ```js
   const SUPABASE_URL      = "https://YOUR-PROJECT.supabase.co";
   const SUPABASE_ANON_KEY = "eyJhbGciOi...";
   const STORAGE_BUCKET    = "grow-photos";
   ```

3. Save. Reload the page and sign in. The sync pill in the top-right should turn green and read **Synced**.

---

## Deploying

Already deployed via GitHub Pages from the `main` branch root → <https://akapc.github.io/hillbilly-grow-tracker/>.

To deploy your own fork: **Settings → Pages → Build and deployment → Source: Deploy from a branch → Branch: `main` / root → Save.**

Because `index.html` is a single static file with no build step, that's the entire deploy.

---

## Security notes

- The anon key in `index.html` is public by design. On its own it grants nothing: every table and the photo bucket require a signed-in user whose email is in `allowed_emails`.
- Keep sign-ups turned off. Even if someone did create an account, they would see no data unless you add their email to `allowed_emails`.
- Photos are private. The app requests signed links that expire after an hour.
- **Upgrading an older install:** earlier versions of `schema.sql` gave the `anon` role full access and made the photo bucket public. Re-run the current `schema.sql`, then do step 3 above. Photos uploaded before the upgrade keep working; their old public links stop working.

---

## File layout

```
hillbilly-grow-tracker/
├── index.html      # the entire app — HTML, CSS, JS, Supabase client via CDN
├── schema.sql      # tables + allow-list RLS + Realtime publication + private storage bucket
├── README.md       # this file
└── .gitignore      # excludes .env and other secrets
```

## Reference data hardcoded in the app

| Setting | Value |
| --- | --- |
| Strain | Hillbilly (P. cubensis) |
| Colonization temp | 77°F |
| Fruiting temp | 74–76°F |
| Humidity target | 90–95% |
| Expected colonization | 7–14 days |
| Expected pinning after flip | 5–14 days |
| Expected flushes | 3–5 |
| Spawn ratio | 1:2 (sandwich tek) |
| Inkbird | TS=77, HD=1, CD=1, AH=85, AL=70 |

## Phases tracked

1. Prep & Spawn to Bulk
2. Colonization
3. Casing & Fruiting Flip
4. Pinning & Fruiting
5. Harvest
6. Reflush
