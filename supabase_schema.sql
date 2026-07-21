-- NOTE: `create table if not exists` below does NOT add new columns to a
-- table that already exists. Every time a column is added here, an existing
-- deployed database needs the matching ALTER TABLE run manually, e.g.:
--   alter table public.trading_sessions add column if not exists news_events jsonb default '[]'::jsonb;
-- Skipping this breaks sync for ALL sessions (not just ones using the new
-- field), since toDb() sends every column on every upsert.
--
-- Run this on an existing database to add the Open vs Prior VA column — the user's own
-- Above/Inside/Below judgment of where a session's open traded relative to the relevant prior
-- session's Value Area, entered directly (no numeric VA levels are stored or computed):
--   alter table public.trading_sessions add column if not exists open_vs_va text check (open_vs_va in ('Above','Inside','Below') or open_vs_va is null);
--
-- Run this on an existing database to add the Macro tab's 10Y Real Yield (TIPS) / Nominal Yield
-- columns — fetched live from Treasury.gov's free daily yield curve feeds and attached to a
-- session automatically on save (see fetchMacroYields/macroForDate in index.html), not entered
-- by hand:
--   alter table public.trading_sessions add column if not exists real_yield_10y numeric;
--   alter table public.trading_sessions add column if not exists nominal_yield_10y numeric;
--
-- If you previously ran an earlier version of this migration that added numeric VA columns
-- (va_high, va_low, prev_week_va_high/low, prev_day_va_high/low, prev_ny_va_high/low,
-- london_va_high/low), those are no longer used and can be dropped:
--   alter table public.trading_sessions drop column if exists va_high;
--   alter table public.trading_sessions drop column if exists va_low;
--   alter table public.trading_sessions drop column if exists prev_week_va_high;
--   alter table public.trading_sessions drop column if exists prev_week_va_low;
--   alter table public.trading_sessions drop column if exists prev_day_va_high;
--   alter table public.trading_sessions drop column if exists prev_day_va_low;
--   alter table public.trading_sessions drop column if exists prev_ny_va_high;
--   alter table public.trading_sessions drop column if exists prev_ny_va_low;
--   alter table public.trading_sessions drop column if exists london_va_high;
--   alter table public.trading_sessions drop column if exists london_va_low;
--
-- Run this on an existing database to add the Current Session IB Hit / Previous Session IB Hit
-- columns — replacing the old numeric IB High/IB Low fields with a direct Yes/No/blank judgment
-- of whether that session's (or the previous session's) Initial Balance was hit, entered the same
-- way as FR/HR/QR/ER Hit:
--   alter table public.trading_sessions add column if not exists ib_current_hit text check (ib_current_hit in ('Yes','No') or ib_current_hit is null);
--   alter table public.trading_sessions add column if not exists ib_prev_hit text check (ib_prev_hit in ('Yes','No') or ib_prev_hit is null);
-- The old ib_high/ib_low numeric columns are no longer used and can be dropped:
--   alter table public.trading_sessions drop column if exists ib_high;
--   alter table public.trading_sessions drop column if exists ib_low;

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

  open_vs_va text check (open_vs_va in ('Above','Inside','Below') or open_vs_va is null),

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

  ib_current_hit text check (ib_current_hit in ('Yes','No') or ib_current_hit is null),
  ib_prev_hit text check (ib_prev_hit in ('Yes','No') or ib_prev_hit is null),
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

  -- Macro tab: 10Y real (TIPS) and nominal Treasury yields, fetched live from Treasury.gov and
  -- attached automatically on session save — not a form field.
  real_yield_10y numeric,
  nominal_yield_10y numeric,

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

-- Trade Entries — logs the mechanics of each individual entry you take (setup/trigger,
-- timing vs the signal, distance from the reference level you were trading against,
-- execution/slippage, and order-flow/footprint context), separate from the session-level
-- price-direction data above.
-- Existing databases: run this whole `create table` block once to add the table. If you
-- already created this table before the order-flow columns (volume, volume_node, footprint,
-- delta_divergence_30m, institutional_trades) existed, add them with:
--   alter table public.trade_entries add column if not exists volume numeric;
--   alter table public.trade_entries add column if not exists volume_node text check (volume_node in ('HVN','LVN') or volume_node is null);
--   alter table public.trade_entries add column if not exists footprint text check (footprint in ('Volume','Absorption','Support','Resistance') or footprint is null);
--   alter table public.trade_entries add column if not exists delta_divergence_30m text check (delta_divergence_30m in ('Yes','No','N/A') or delta_divergence_30m is null);
--   alter table public.trade_entries add column if not exists institutional_trades jsonb default '[]'::jsonb;
--
-- If you already created the table before the Bookmap/order-book and footprint-context columns
-- (book_imbalance, liquidity_at_level, stacked_imbalances, imbalance_side, absorption_side,
-- exhaustion, delta_at_entry, cum_delta_trend, rotations_before_entry, poc_va_position) existed,
-- add them with:
--   alter table public.trade_entries add column if not exists book_imbalance numeric;
--   alter table public.trade_entries add column if not exists liquidity_at_level text check (liquidity_at_level in ('Thin','Normal','Stacked') or liquidity_at_level is null);
--   alter table public.trade_entries add column if not exists stacked_imbalances numeric;
--   alter table public.trade_entries add column if not exists imbalance_side text check (imbalance_side in ('Buy','Sell') or imbalance_side is null);
--   alter table public.trade_entries add column if not exists absorption_side text check (absorption_side in ('Buyers Absorbed (High)','Sellers Absorbed (Low)') or absorption_side is null);
--   alter table public.trade_entries add column if not exists exhaustion text check (exhaustion in ('Yes','No') or exhaustion is null);
--   alter table public.trade_entries add column if not exists delta_at_entry numeric;
--   alter table public.trade_entries add column if not exists cum_delta_trend text check (cum_delta_trend in ('Rising','Falling','Flat') or cum_delta_trend is null);
--   alter table public.trade_entries add column if not exists rotations_before_entry numeric;
--   alter table public.trade_entries add column if not exists poc_va_position text check (poc_va_position in ('Inside Value','Outside Value','At VAL','At VAH','At POC') or poc_va_position is null);
--
-- If you already created the table before the indicator-context columns (vwap_level,
-- bollinger_band, ema_6m, ema_30m, ema_1h) existed, add them with:
--   alter table public.trade_entries add column if not exists vwap_level text check (vwap_level in ('Middle','Std1','Std2') or vwap_level is null);
--   alter table public.trade_entries add column if not exists bollinger_band text check (bollinger_band in ('Middle','Below Lower Band','Above Lower Band','Upper Band','Lower Band') or bollinger_band is null);
--   alter table public.trade_entries add column if not exists ema_6m text check (ema_6m in ('5','8') or ema_6m is null);
--   alter table public.trade_entries add column if not exists ema_30m text check (ema_30m in ('21','60') or ema_30m is null);
--   alter table public.trade_entries add column if not exists ema_1h text check (ema_1h in ('8','21','60') or ema_1h is null);
--
-- If you already created the table before the delta_absolute column existed, add it with:
--   alter table public.trade_entries add column if not exists delta_absolute numeric;
--
-- If you already created the table before the stop_loss_price/exit_price columns existed
-- (used to auto-calculate result_r as P&L / entry-to-stop risk, and to flag exit slippage vs
-- the planned stop), add them with:
--   alter table public.trade_entries add column if not exists stop_loss_price numeric;
--   alter table public.trade_entries add column if not exists exit_price numeric;
--
-- If you already created the table before the screenshots column existed, add it with:
--   alter table public.trade_entries add column if not exists screenshots jsonb default '[]'::jsonb;
-- Screenshots are stored as compressed base64 JPEG data URLs inside this jsonb column (same
-- approach as institutional_trades/news_events), not in Supabase Storage. That keeps setup to
-- just this one table, but every save re-upserts the full row including all attached images —
-- fine for a personal journal with a few compressed screenshots per entry, but if you start
-- attaching many large images per entry this will bloat both the database and the browser's
-- localStorage. Ask to switch to Supabase Storage (file bucket + a URL reference column here)
-- if that becomes a problem.
create table if not exists public.trade_entries (
  id uuid primary key,
  user_id uuid references auth.users(id),
  date date,
  session_type text check (session_type in ('Weekly','Daily','London','New York') or session_type is null),
  market text,
  direction text check (direction in ('Long','Short') or direction is null),
  setup_type text,
  order_type text check (order_type in ('Limit','Market','Stop') or order_type is null),

  signal_time text,
  entry_time text,
  intended_price numeric,
  entry_price numeric,
  stop_loss_price numeric,
  exit_price numeric,

  reference_label text,
  reference_price numeric,
  result_r numeric,

  volume numeric,
  volume_node text check (volume_node in ('HVN','LVN') or volume_node is null),
  footprint text check (footprint in ('Volume','Absorption','Support','Resistance') or footprint is null),
  delta_divergence_30m text check (delta_divergence_30m in ('Yes','No','N/A') or delta_divergence_30m is null),
  institutional_trades jsonb default '[]'::jsonb,

  book_imbalance numeric,
  liquidity_at_level text check (liquidity_at_level in ('Thin','Normal','Stacked') or liquidity_at_level is null),
  stacked_imbalances numeric,
  imbalance_side text check (imbalance_side in ('Buy','Sell') or imbalance_side is null),
  absorption_side text check (absorption_side in ('Buyers Absorbed (High)','Sellers Absorbed (Low)') or absorption_side is null),
  exhaustion text check (exhaustion in ('Yes','No') or exhaustion is null),
  delta_at_entry numeric,
  delta_absolute numeric,
  cum_delta_trend text check (cum_delta_trend in ('Rising','Falling','Flat') or cum_delta_trend is null),
  rotations_before_entry numeric,
  poc_va_position text check (poc_va_position in ('Inside Value','Outside Value','At VAL','At VAH','At POC') or poc_va_position is null),

  vwap_level text check (vwap_level in ('Middle','Std1','Std2') or vwap_level is null),
  bollinger_band text check (bollinger_band in ('Middle','Below Lower Band','Above Lower Band','Upper Band','Lower Band') or bollinger_band is null),
  ema_6m text check (ema_6m in ('5','8') or ema_6m is null),
  ema_30m text check (ema_30m in ('21','60') or ema_30m is null),
  ema_1h text check (ema_1h in ('8','21','60') or ema_1h is null),

  screenshots jsonb default '[]'::jsonb,

  notes text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.trade_entries enable row level security;

drop policy if exists "select own trade entries" on public.trade_entries;
drop policy if exists "insert own trade entries" on public.trade_entries;
drop policy if exists "update own trade entries" on public.trade_entries;
drop policy if exists "delete own trade entries" on public.trade_entries;

create policy "select own trade entries" on public.trade_entries
for select using (auth.uid() = user_id);

create policy "insert own trade entries" on public.trade_entries
for insert with check (auth.uid() = user_id);

create policy "update own trade entries" on public.trade_entries
for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "delete own trade entries" on public.trade_entries
for delete using (auth.uid() = user_id);

create index if not exists trade_entries_date_idx on public.trade_entries(date);
create index if not exists trade_entries_setup_type_idx on public.trade_entries(setup_type);
create index if not exists trade_entries_user_id_idx on public.trade_entries(user_id);
