-- ============================================================================
-- Hillbilly Monotub Grow Tracker — Supabase Schema
-- ============================================================================
-- Run this entire file in Supabase Dashboard -> SQL Editor -> New query.
-- Safe to re-run: uses IF NOT EXISTS / DROP POLICY IF EXISTS guards.
-- Re-running it on an older install upgrades it: the open anon policies are
-- removed and the photo bucket becomes private. See ACCESS CONTROL below.
-- ============================================================================

-- Required for uuid_generate_v4()
create extension if not exists "uuid-ossp";

-- ----------------------------------------------------------------------------
-- TABLES
-- ----------------------------------------------------------------------------

create table if not exists public.tubs (
    id uuid primary key default uuid_generate_v4(),
    tub_number int not null check (tub_number between 1 and 3),
    strain text not null default 'Hillbilly',
    inoculation_date timestamptz,
    current_phase int not null default 1 check (current_phase between 1 and 6),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create unique index if not exists tubs_tub_number_unique on public.tubs(tub_number);

create table if not exists public.phase_log (
    id uuid primary key default uuid_generate_v4(),
    tub_id uuid not null references public.tubs(id) on delete cascade,
    phase_number int not null,
    entered_at timestamptz not null default now(),
    notes text
);

create table if not exists public.observations (
    id uuid primary key default uuid_generate_v4(),
    tub_id uuid not null references public.tubs(id) on delete cascade,
    timestamp timestamptz not null default now(),
    note text,
    photo_url text
);

create table if not exists public.harvests (
    id uuid primary key default uuid_generate_v4(),
    tub_id uuid not null references public.tubs(id) on delete cascade,
    flush_number int not null,
    harvest_date timestamptz not null default now(),
    wet_weight_g numeric,
    dry_weight_g numeric,
    notes text,
    photo_url text
);

create table if not exists public.contamination_events (
    id uuid primary key default uuid_generate_v4(),
    tub_id uuid not null references public.tubs(id) on delete cascade,
    detected_at timestamptz not null default now(),
    type text check (type in ('green','black','pink','other')),
    action_taken text,
    photo_url text,
    notes text
);

-- Auto-bump updated_at on tubs row writes
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
    new.updated_at = now();
    return new;
end$$;

drop trigger if exists tubs_touch_updated_at on public.tubs;
create trigger tubs_touch_updated_at
    before update on public.tubs
    for each row execute function public.touch_updated_at();

-- ----------------------------------------------------------------------------
-- ACCESS CONTROL
-- ----------------------------------------------------------------------------
-- Only signed-in users whose email is listed in public.allowed_emails can read
-- or write anything. The anon key alone grants no access, so it is safe to
-- ship in index.html.
--
-- One-time setup, after running this file:
--   1. Dashboard -> Authentication -> Users -> Add user (email + password).
--   2. SQL Editor:  insert into public.allowed_emails values ('you@example.com');
--   3. Dashboard -> Authentication -> Sign In / Providers -> turn OFF
--      "Allow new users to sign up".
-- ----------------------------------------------------------------------------

create table if not exists public.allowed_emails (
    email text primary key
);
-- RLS on with no policies: not readable or writable through the API at all.
alter table public.allowed_emails enable row level security;

create or replace function public.is_allowed()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.allowed_emails a
        where lower(a.email) = lower(auth.jwt() ->> 'email')
    );
$$;

revoke all on function public.is_allowed() from public, anon;
grant execute on function public.is_allowed() to authenticated;

alter table public.tubs                  enable row level security;
alter table public.phase_log             enable row level security;
alter table public.observations          enable row level security;
alter table public.harvests              enable row level security;
alter table public.contamination_events  enable row level security;

do $$
declare
    t text;
begin
    foreach t in array array['tubs','phase_log','observations','harvests','contamination_events']
    loop
        -- remove the old open-to-anon policies from earlier versions of this file
        execute format('drop policy if exists "Allow anon read access"   on public.%I', t);
        execute format('drop policy if exists "Allow anon write access"  on public.%I', t);
        execute format('drop policy if exists "Allow anon update access" on public.%I', t);
        execute format('drop policy if exists "Allow anon delete access" on public.%I', t);

        execute format('drop policy if exists "Allowed users full access" on public.%I', t);
        execute format(
            'create policy "Allowed users full access" on public.%I for all to authenticated '
            'using ((select public.is_allowed())) with check ((select public.is_allowed()))', t);
    end loop;
end$$;

-- ----------------------------------------------------------------------------
-- REALTIME PUBLICATION
-- ----------------------------------------------------------------------------
-- Tables added to supabase_realtime broadcast change events. The app
-- subscribes to all of these so multiple devices stay in sync. Realtime
-- applies the same RLS policies, so only allowed users receive changes.
-- ----------------------------------------------------------------------------
do $$
declare
    t text;
begin
    if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
        create publication supabase_realtime;
    end if;
    foreach t in array array['tubs','phase_log','observations','harvests','contamination_events']
    loop
        if not exists (
            select 1 from pg_publication_tables
            where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
        ) then
            execute format('alter publication supabase_realtime add table public.%I', t);
        end if;
    end loop;
end$$;

-- ----------------------------------------------------------------------------
-- STORAGE BUCKET: grow-photos
-- ----------------------------------------------------------------------------
-- Private bucket. The app stores the object path and shows photos through
-- short-lived signed URLs, so a leaked link stops working within the hour.
-- ----------------------------------------------------------------------------

insert into storage.buckets (id, name, public)
values ('grow-photos', 'grow-photos', false)
on conflict (id) do update set public = excluded.public;

-- remove the old public / anon policies from earlier versions of this file
drop policy if exists "grow-photos public read"   on storage.objects;
drop policy if exists "grow-photos anon insert"   on storage.objects;
drop policy if exists "grow-photos anon update"   on storage.objects;
drop policy if exists "grow-photos anon delete"   on storage.objects;

drop policy if exists "grow-photos allowed users" on storage.objects;
create policy "grow-photos allowed users" on storage.objects
    for all to authenticated
    using (bucket_id = 'grow-photos' and (select public.is_allowed()))
    with check (bucket_id = 'grow-photos' and (select public.is_allowed()));

-- ----------------------------------------------------------------------------
-- SEED: three tub rows so the dashboard renders out of the box
-- ----------------------------------------------------------------------------
insert into public.tubs (tub_number, strain, current_phase)
values (1, 'Hillbilly', 1), (2, 'Hillbilly', 1), (3, 'Hillbilly', 1)
on conflict (tub_number) do nothing;
