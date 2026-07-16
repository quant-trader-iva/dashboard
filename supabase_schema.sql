-- NOTE: `create table if not exists` below does NOT add new columns to a
-- table that already exists. Every time a column is added here, an existing
-- deployed database needs the matching ALTER TABLE run manually, e.g.:
--   alter table public.trading_sessions add column if not exists news_events jsonb default '[]'::jsonb;
-- Skipping this breaks sync for ALL sessions (not just ones using the new
-- field), since toDb() sends every column on every upsert.
--
-- Run this on an existing database to add the per-side FR/HR/QR/ER hit columns:
--   alter table public.trading_sessions add column if not exists up_fr_hit text check (up_fr_hit in ('Yes','No') or up_fr_hit is null);
--   alter table public.trading_sessions add column if not exists down_fr_hit text check (down_fr_hit in ('Yes','No') or down_fr_hit is null);
--   alter table public.trading_sessions add column if not exists up_hr_hit text check (up_hr_hit in ('Yes','No') or up_hr_hit is null);
--   alter table public.trading_sessions add column if not exists down_hr_hit text check (down_hr_hit in ('Yes','No') or down_hr_hit is null);
--   alter table public.trading_sessions add column if not exists up_qr_hit text check (up_qr_hit in ('Yes','No') or up_qr_hit is null);
--   alter table public.trading_sessions add column if not exists down_qr_hit text check (down_qr_hit in ('Yes','No') or down_qr_hit is null);
--   alter table public.trading_sessions add column if not exists up_er_hit text check (up_er_hit in ('Yes','No') or up_er_hit is null);
--   alter table public.trading_sessions add column if not exists down_er_hit text check (down_er_hit in ('Yes','No') or down_er_hit is null);
--
-- Run this on an existing database to add the Value Area columns (manually-entered
-- per session, used to check whether the next session's open traded above/inside/below it):
--   alter table public.trading_sessions add column if not exists va_high numeric;
--   alter table public.trading_sessions add column if not exists va_low numeric;

create table if not exists public.trading_sessions (
  id uuid primary key,
  user_id uuid references auth.users(id),
  date date,
  day text,
  session_type text check (session_type in ('Weekly','Daily','London','New York') or session_type is null),
  market text,
  day_type text,
  open_type text,
  bias text,
  outcome text,

  prev_week_high numeric,
  prev_week_low numeric,
  prev_day_high numeric,
  prev_day_low numeric,
  prev_ny_high numeric,
  prev_ny_low numeric,
  london_high numeric,
  london_low numeric,

  open_range_open numeric,
  open_range_close numeric,
  close_range_open numeric,
  close_range_close numeric,

  high numeric,
  high_time text,
  low numeric,
  low_time text,
  poc numeric,
  vpoc numeric,
  va_high numeric,
  va_low numeric,

  ib_high numeric,
  ib_low numeric,
  ny_high numeric,
  ny_low numeric,
  extreme_high numeric,
  extreme_low numeric,

  volume numeric,
  open_interest numeric,
  delta_finish numeric,
  result_r numeric,
  tpos numeric,
  confidence_score numeric,

  fr_hit text check (fr_hit in ('Yes','No') or fr_hit is null),
  hr_hit text check (hr_hit in ('Yes','No') or hr_hit is null),
  qr_hit text check (qr_hit in ('Yes','No') or qr_hit is null),
  er_hit text check (er_hit in ('Yes','No') or er_hit is null),
  up_total_hit text check (up_total_hit in ('Yes','No') or up_total_hit is null),
  down_total_hit text check (down_total_hit in ('Yes','No') or down_total_hit is null),
  up_fr_hit text check (up_fr_hit in ('Yes','No') or up_fr_hit is null),
  down_fr_hit text check (down_fr_hit in ('Yes','No') or down_fr_hit is null),
  up_hr_hit text check (up_hr_hit in ('Yes','No') or up_hr_hit is null),
  down_hr_hit text check (down_hr_hit in ('Yes','No') or down_hr_hit is null),
  up_qr_hit text check (up_qr_hit in ('Yes','No') or up_qr_hit is null),
  down_qr_hit text check (down_qr_hit in ('Yes','No') or down_qr_hit is null),
  up_er_hit text check (up_er_hit in ('Yes','No') or up_er_hit is null),
  down_er_hit text check (down_er_hit in ('Yes','No') or down_er_hit is null),

  news_events jsonb default '[]'::jsonb,

  notes text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.trading_sessions enable row level security;

drop policy if exists "allow anon dashboard access" on public.trading_sessions;
drop policy if exists "select own sessions" on public.trading_sessions;
drop policy if exists "insert own sessions" on public.trading_sessions;
drop policy if exists "update own sessions" on public.trading_sessions;
drop policy if exists "delete own sessions" on public.trading_sessions;

create policy "select own sessions" on public.trading_sessions
for select using (auth.uid() = user_id);

create policy "insert own sessions" on public.trading_sessions
for insert with check (auth.uid() = user_id);

create policy "update own sessions" on public.trading_sessions
for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "delete own sessions" on public.trading_sessions
for delete using (auth.uid() = user_id);

create index if not exists trading_sessions_date_idx on public.trading_sessions(date);
create index if not exists trading_sessions_session_type_idx on public.trading_sessions(session_type);
create index if not exists trading_sessions_day_type_idx on public.trading_sessions(day_type);
create index if not exists trading_sessions_open_type_idx on public.trading_sessions(open_type);
create index if not exists trading_sessions_user_id_idx on public.trading_sessions(user_id);

-- Enforces one session per user/date/session_type at the database level, as a
-- backstop for the app's client-side duplicate check (which only guards the
-- Session Entry form and can't see rows written by another device/tab before
-- a sync, or rows brought in via Import Backup).
-- On an EXISTING database, this will fail if duplicate (user_id, date,
-- session_type) rows already exist — find and delete/merge them first, e.g.:
--   select user_id, date, session_type, count(*) from public.trading_sessions
--   group by 1,2,3 having count(*) > 1;
create unique index if not exists trading_sessions_user_date_type_uidx
  on public.trading_sessions(user_id, date, session_type);

-- Position Sizing calculator settings — one row per user, synced across devices.
create table if not exists public.position_sizing (
  user_id uuid primary key references auth.users(id),
  account_size numeric,
  currency text,
  leverage text,
  lot_size numeric,
  point_value numeric,
  notional numeric,
  updated_at timestamptz default now()
);

alter table public.position_sizing enable row level security;

drop policy if exists "select own position sizing" on public.position_sizing;
drop policy if exists "insert own position sizing" on public.position_sizing;
drop policy if exists "update own position sizing" on public.position_sizing;
drop policy if exists "delete own position sizing" on public.position_sizing;

create policy "select own position sizing" on public.position_sizing
for select using (auth.uid() = user_id);

create policy "insert own position sizing" on public.position_sizing
for insert with check (auth.uid() = user_id);

create policy "update own position sizing" on public.position_sizing
for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "delete own position sizing" on public.position_sizing
for delete using (auth.uid() = user_id);
