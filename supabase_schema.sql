
create table if not exists public.trading_sessions (
  id uuid primary key,
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
  low numeric,
  poc numeric,
  vpoc numeric,

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

  notes text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.trading_sessions enable row level security;

drop policy if exists "allow anon dashboard access" on public.trading_sessions;
create policy "allow anon dashboard access"
on public.trading_sessions
for all
using (true)
with check (true);

create index if not exists trading_sessions_date_idx on public.trading_sessions(date);
create index if not exists trading_sessions_session_type_idx on public.trading_sessions(session_type);
create index if not exists trading_sessions_day_type_idx on public.trading_sessions(day_type);
create index if not exists trading_sessions_open_type_idx on public.trading_sessions(open_type);
