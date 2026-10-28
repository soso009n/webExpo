-- ============================================================================
-- RIVER FLOW GUARDIAN - SCADA WEB MONITORING SUNGAI
-- Supabase PostgreSQL Schema - Production Ready
-- ============================================================================
-- Jalankan file ini di Supabase SQL Editor secara berurutan dari atas ke bawah.
-- Membutuhkan extension: pgcrypto (gen_random_uuid), pg_trgm (opsional search)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. EXTENSIONS
-- ----------------------------------------------------------------------------
create extension if not exists "pgcrypto";
create extension if not exists "pg_trgm";

-- ----------------------------------------------------------------------------
-- 1. TABEL: stations
-- ----------------------------------------------------------------------------
create table if not exists public.stations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  location text not null,
  latitude float8,
  longitude float8,
  description text,
  status text not null default 'active'
    check (status in ('active', 'inactive', 'maintenance')),
  river_name text,
  installation_date date,
  elevation_m float8,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.stations is 'Stasiun pemantauan sungai (SCADA site)';

-- ----------------------------------------------------------------------------
-- 2. TABEL: devices
-- ----------------------------------------------------------------------------
create table if not exists public.devices (
  id uuid primary key default gen_random_uuid(),
  station_id uuid references public.stations(id) on delete cascade,
  name text not null,
  device_type text not null
    check (device_type in ('radar_flowmeter', 'power_meter', 'plc', 'gateway', 'modem')),
  protocol text not null default 'modbus_rtu'
    check (protocol in ('modbus_rtu', 'modbus_tcp', 'mqtt', 'https', 'opc_ua')),
  modbus_address integer,
  ip_address text,
  port integer,
  firmware_version text,
  manufacturer text,
  model text,
  serial_number text,
  status text not null default 'online'
    check (status in ('online', 'offline', 'error', 'maintenance')),
  last_seen timestamptz,
  scan_interval_sec integer not null default 5,
  enabled boolean not null default true,
  config jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.devices is 'Perangkat fisik SCADA (radar, power meter, PLC, gateway)';

-- ----------------------------------------------------------------------------
-- 3. TABEL: tags
-- ----------------------------------------------------------------------------
create table if not exists public.tags (
  id uuid primary key default gen_random_uuid(),
  device_id uuid references public.devices(id) on delete set null,
  station_id uuid references public.stations(id) on delete cascade,
  tag_id text unique not null, -- contoh: 'HYDRO.WATER_LEVEL'
  name text not null,
  description text,
  value_type text not null default 'float'
    check (value_type in ('float', 'integer', 'boolean', 'string')),
  unit text,
  source_address text,
  alarm_high float8,
  alarm_high_high float8,
  alarm_low float8,
  alarm_low_low float8,
  deadband float8 not null default 0,
  enabled boolean not null default true,
  display_precision integer not null default 3,
  created_at timestamptz not null default now()
);

alter table public.tags add column if not exists deadband float8 not null default 0;
alter table public.tags add column if not exists enabled boolean not null default true;
alter table public.tags add column if not exists display_precision integer not null default 3;

do $$
begin
  alter table public.tags add constraint tags_deadband_nonnegative check (deadband >= 0);
exception when duplicate_object then
  null;
end $$;

comment on table public.tags is 'Definisi tag/point data sensor (point configuration)';

-- ----------------------------------------------------------------------------
-- 4. TABEL: measurements (time-series, partitioned by month)
-- ----------------------------------------------------------------------------
-- Parent table partitioned by range on source_timestamp.
create table if not exists public.measurements (
  id bigserial not null,
  tag_id text not null references public.tags(tag_id) on delete cascade,
  station_id uuid references public.stations(id) on delete cascade,
  value float8,
  quality text not null default 'good'
    check (quality in ('good', 'bad', 'uncertain', 'stale', 'comm_failure')),
  source_timestamp timestamptz not null,
  received_timestamp timestamptz not null default now(),
  sequence_id bigint,
  raw_value text,
  primary key (id, source_timestamp)
) partition by range (source_timestamp);

comment on table public.measurements is 'Data historis sensor time-series, dipartisi per bulan';

-- Helper function untuk membuat partisi bulan secara otomatis.
create or replace function public.create_measurements_partition(for_date date)
returns void
language plpgsql
as $$
declare
  part_start date := date_trunc('month', for_date)::date;
  part_end date := (date_trunc('month', for_date) + interval '1 month')::date;
  part_name text := 'measurements_' || to_char(part_start, 'YYYY_MM');
begin
  if not exists (
    select 1 from pg_class where relname = part_name
  ) then
    execute format(
      'create table public.%I partition of public.measurements for values from (%L) to (%L);',
      part_name, part_start, part_end
    );
    execute format(
      'create index %I on public.%I (tag_id, source_timestamp desc);',
      part_name || '_tag_ts_idx', part_name
    );
    execute format(
      'create index %I on public.%I (station_id, source_timestamp desc);',
      part_name || '_station_ts_idx', part_name
    );
  end if;
end;
$$;

-- Buat partisi untuk 2 bulan lalu, bulan ini, dan 3 bulan ke depan.
do $$
declare
  i integer;
begin
  for i in -2..3 loop
    perform public.create_measurements_partition((now() + (i || ' month')::interval)::date);
  end loop;
end $$;

-- ----------------------------------------------------------------------------
-- 5. TABEL: alarms
-- ----------------------------------------------------------------------------
create table if not exists public.alarms (
  id uuid primary key default gen_random_uuid(),
  station_id uuid references public.stations(id) on delete cascade,
  tag_id text references public.tags(tag_id) on delete set null,
  alarm_type text not null
    check (alarm_type in ('high_high', 'high', 'low', 'low_low', 'comm_failure', 'data_stale', 'device_offline', 'system', 'manual')),
  priority text not null
    check (priority in ('critical', 'high', 'medium', 'low', 'info')),
  message text not null,
  device_id uuid references public.devices(id) on delete set null,
  value_at_alarm float8,
  threshold_value float8,
  status text not null default 'active'
    check (status in ('active', 'acknowledged', 'cleared', 'suppressed')),
  active_at timestamptz not null default now(),
  acknowledged_at timestamptz,
  acknowledged_by uuid references auth.users(id),
  ack_comment text,
  cleared_at timestamptz,
  cleared_by uuid references auth.users(id),
  duration_seconds integer,
  created_at timestamptz not null default now()
);

comment on table public.alarms is 'Alarm aktif dan riwayat alarm sistem';

-- Migration idempoten untuk database yang sudah dibuat dengan schema lama.
alter table public.alarms add column if not exists device_id uuid references public.devices(id) on delete set null;
do $$
declare
  v_constraint text;
begin
  select conname into v_constraint
  from pg_constraint
  where conrelid = 'public.alarms'::regclass
    and contype = 'c'
    and pg_get_constraintdef(oid) like '%alarm_type%'
  limit 1;
  if v_constraint is not null then
    execute format('alter table public.alarms drop constraint %I', v_constraint);
  end if;
  alter table public.alarms add constraint alarms_alarm_type_check
    check (alarm_type in ('high_high', 'high', 'low', 'low_low', 'comm_failure', 'data_stale', 'device_offline', 'system', 'manual'));
exception when duplicate_object then
  null;
end $$;

-- ----------------------------------------------------------------------------
-- 6. TABEL: events (audit trail)
-- ----------------------------------------------------------------------------
create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  station_id uuid references public.stations(id) on delete set null,
  event_type text not null
    check (event_type in ('login', 'logout', 'command', 'config_change', 'alarm_ack', 'alarm_clear', 'device_change', 'user_change', 'system', 'data_correction')),
  severity text not null default 'info'
    check (severity in ('critical', 'warning', 'info', 'debug')),
  message text not null,
  actor_id uuid references auth.users(id),
  actor_email text,
  actor_role text,
  device_id uuid references public.devices(id) on delete set null,
  tag_id text,
  old_value text,
  new_value text,
  ip_address text,
  user_agent text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

comment on table public.events is 'Audit trail seluruh aktivitas sistem dan operator';

-- ----------------------------------------------------------------------------
-- 7. TABEL: commands
-- ----------------------------------------------------------------------------
create table if not exists public.commands (
  id uuid primary key default gen_random_uuid(),
  station_id uuid references public.stations(id) on delete cascade,
  device_id uuid references public.devices(id) on delete cascade,
  tag_id text,
  command_type text not null
    check (command_type in ('start', 'stop', 'reset', 'setpoint', 'open', 'close', 'acknowledge', 'mode_change', 'write_tag', 'restart_device', 'enable_device', 'disable_device', 'ack_all_alarms')),
  value text,
  status text not null default 'pending'
    check (status in ('pending', 'sent', 'executed', 'failed', 'rejected')),
  requested_by uuid references auth.users(id),
  requested_at timestamptz not null default now(),
  executed_at timestamptz,
  response text,
  interlock_status text,
  reject_reason text
);

comment on table public.commands is 'Perintah operator yang dikirim ke perangkat lapangan';

-- Migration idempoten: schema lama belum mengenal command device.
do $$
declare
  v_constraint text;
begin
  select conname into v_constraint
  from pg_constraint
  where conrelid = 'public.commands'::regclass
    and contype = 'c'
    and pg_get_constraintdef(oid) like '%command_type%'
  limit 1;
  if v_constraint is not null then
    execute format('alter table public.commands drop constraint %I', v_constraint);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.commands'::regclass and conname = 'commands_command_type_check'
  ) then
    alter table public.commands add constraint commands_command_type_check
      check (command_type in ('start', 'stop', 'reset', 'setpoint', 'open', 'close', 'acknowledge', 'mode_change', 'write_tag', 'restart_device', 'enable_device', 'disable_device', 'ack_all_alarms'));
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- 8. TABEL: profiles (extend auth.users)
-- ----------------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  role text not null default 'viewer'
    check (role in ('superadmin', 'admin', 'operator', 'technician', 'viewer')),
  station_access uuid[] not null default '{}',
  phone text,
  avatar_url text,
  is_active boolean not null default true,
  last_login timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.profiles is 'Profil pengguna, extend auth.users Supabase';

-- ----------------------------------------------------------------------------
-- 9. TABEL: monthly_reports
-- ----------------------------------------------------------------------------
create table if not exists public.monthly_reports (
  id uuid primary key default gen_random_uuid(),
  station_id uuid references public.stations(id) on delete cascade,
  report_date date not null,
  total_energy_kwh float8,
  avg_power_kw float8,
  max_power_kw float8,
  min_power_kw float8,
  operational_hours float8,
  avg_water_level_m float8,
  max_water_level_m float8,
  min_water_level_m float8,
  avg_flow_rate_m3s float8,
  max_flow_rate_m3s float8,
  availability_percent float8,
  capacity_factor_percent float8,
  total_alarms integer,
  critical_alarms integer,
  data_quality_percent float8,
  notes text,
  created_by uuid references auth.users(id),
  is_auto_generated boolean not null default false,
  created_at timestamptz not null default now()
);

comment on table public.monthly_reports is 'Laporan bulanan produksi dan performa stasiun';

-- ----------------------------------------------------------------------------
-- 10. TABEL: breakdown_reports
-- ----------------------------------------------------------------------------
create table if not exists public.breakdown_reports (
  id uuid primary key default gen_random_uuid(),
  station_id uuid references public.stations(id) on delete cascade,
  event_date date not null,
  outage_start timestamptz,
  outage_end timestamptz,
  duration_hours float8,
  load_at_outage_kw float8,
  energy_not_served_kwh float8,
  cause text not null,
  cause_category text
    check (cause_category in ('lightning', 'mechanical', 'electrical', 'communication', 'flood', 'maintenance', 'other')),
  affected_devices text[],
  corrective_action text,
  operator_name text,
  technician_name text,
  status text not null default 'open'
    check (status in ('open', 'in_progress', 'resolved')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

comment on table public.breakdown_reports is 'Laporan gangguan/kerusakan (breakdown) stasiun';

-- ----------------------------------------------------------------------------
-- 11. INDEXES
-- ----------------------------------------------------------------------------
-- Index pada parent measurements akan diturunkan ke setiap partisi secara otomatis
-- (PostgreSQL 11+ mendukung index pada partitioned table).
create index if not exists idx_measurements_tag_ts on public.measurements (tag_id, source_timestamp desc);
create index if not exists idx_measurements_station_ts on public.measurements (station_id, source_timestamp desc);
create index if not exists idx_alarms_station_status_active on public.alarms (station_id, status, active_at desc);
create index if not exists idx_events_station_created on public.events (station_id, created_at desc);
create index if not exists idx_devices_station_status on public.devices (station_id, status);
create index if not exists idx_tags_station on public.tags (station_id);
create index if not exists idx_tags_device on public.tags (device_id);
create index if not exists idx_commands_device_status on public.commands (device_id, status);
create index if not exists idx_alarms_tag on public.alarms (tag_id);
create index if not exists idx_events_actor on public.events (actor_id);

-- ----------------------------------------------------------------------------
-- 12. VIEWS
-- ----------------------------------------------------------------------------

-- latest_measurements: nilai terbaru setiap tag
create or replace view public.latest_measurements as
select distinct on (m.station_id, m.tag_id)
  m.tag_id,
  m.station_id,
  m.value,
  m.quality,
  m.source_timestamp,
  m.received_timestamp,
  t.name as tag_name,
  t.unit,
  t.display_precision,
  t.alarm_high,
  t.alarm_high_high,
  t.alarm_low,
  t.alarm_low_low
from public.measurements m
join public.tags t on t.tag_id = m.tag_id
order by m.station_id, m.tag_id, m.source_timestamp desc, m.received_timestamp desc;

comment on view public.latest_measurements is 'Nilai terbaru untuk setiap tag';

-- active_alarms_view: alarm aktif/acknowledged + info stasiun & tag
-- Drop diperlukan karena device_id ditambahkan ke projection view; PostgreSQL
-- tidak mengizinkan CREATE OR REPLACE mengubah urutan/kolom view.
drop view if exists public.active_alarms_view;
create or replace view public.active_alarms_view as
select
  a.id,
  a.station_id,
  s.name as station_name,
  a.tag_id,
  a.device_id,
  t.name as tag_name,
  t.unit,
  a.alarm_type,
  a.priority,
  a.message,
  a.value_at_alarm,
  a.threshold_value,
  a.status,
  a.active_at,
  a.acknowledged_at,
  a.acknowledged_by,
  a.ack_comment,
  extract(epoch from (now() - a.active_at))::integer as duration_seconds_live
from public.alarms a
left join public.stations s on s.id = a.station_id
left join public.tags t on t.tag_id = a.tag_id
where a.status in ('active', 'acknowledged')
order by
  case a.priority
    when 'critical' then 1
    when 'high' then 2
    when 'medium' then 3
    when 'low' then 4
    else 5
  end,
  a.active_at desc;

comment on view public.active_alarms_view is 'Alarm aktif dan acknowledged beserta info stasiun & tag';

-- device_health_view: status device + menit sejak last_seen + is_online
create or replace view public.device_health_view as
select
  d.id,
  d.station_id,
  d.name,
  d.device_type,
  d.protocol,
  d.status,
  d.last_seen,
  d.enabled,
  d.scan_interval_sec,
  d.firmware_version,
  case
    when d.last_seen is null then null
    else round(extract(epoch from (now() - d.last_seen)) / 60.0, 1)
  end as minutes_since_last_seen,
  case
    when d.last_seen is null then false
    when d.enabled and d.status = 'online'
      and extract(epoch from (now() - d.last_seen)) <= greatest(d.scan_interval_sec * 3, 30) then true
    else false
  end as is_online
from public.devices d;

comment on view public.device_health_view is 'Status kesehatan semua device dengan indikator online/offline';

-- daily_energy_summary: agregat harian untuk tag daya (POWER.ACTIVE_POWER / ENERGY_KWH)
create or replace view public.daily_energy_summary as
select
  m.station_id,
  date_trunc('day', m.source_timestamp)::date as day,
  avg(m.value) filter (where m.tag_id = 'POWER.ACTIVE_POWER') as avg_power_kw,
  max(m.value) filter (where m.tag_id = 'POWER.ACTIVE_POWER') as max_power_kw,
  min(m.value) filter (where m.tag_id = 'POWER.ACTIVE_POWER') as min_power_kw,
  max(m.value) filter (where m.tag_id = 'POWER.ENERGY_KWH') - min(m.value) filter (where m.tag_id = 'POWER.ENERGY_KWH') as total_energy_kwh,
  count(*) filter (where m.tag_id = 'POWER.ACTIVE_POWER') as sample_count
from public.measurements m
where m.tag_id in ('POWER.ACTIVE_POWER', 'POWER.ENERGY_KWH')
group by m.station_id, date_trunc('day', m.source_timestamp)::date
order by day desc;

comment on view public.daily_energy_summary is 'Agregat harian data daya listrik per stasiun';

-- ----------------------------------------------------------------------------
-- 13. FUNCTIONS
-- ----------------------------------------------------------------------------

-- get_station_kpi: ringkasan KPI terkini satu stasiun dalam JSON
create or replace function public.get_station_kpi(p_station_id uuid, p_period_hours integer default 24)
returns json
language plpgsql
stable
as $$
declare
  result json;
begin
  select json_build_object(
    'water_level', (select value from public.latest_measurements where station_id = p_station_id and tag_id = 'HYDRO.WATER_LEVEL'),
    'velocity', (select value from public.latest_measurements where station_id = p_station_id and tag_id = 'HYDRO.VELOCITY'),
    'flow_rate', (select value from public.latest_measurements where station_id = p_station_id and tag_id = 'HYDRO.FLOW_RATE'),
    'active_power', (select value from public.latest_measurements where station_id = p_station_id and tag_id = 'POWER.ACTIVE_POWER'),
    'turbine_rpm', (select value from public.latest_measurements where station_id = p_station_id and tag_id = 'TURBINE.RPM'),
    'daily_energy', (
      select coalesce(max(value) - min(value), 0)
      from public.measurements
      where station_id = p_station_id
        and tag_id = 'POWER.ENERGY_KWH'
        and source_timestamp >= date_trunc('day', now())
    ),
    'active_alarms', (
      select json_build_object(
        'total', count(*),
        'critical', count(*) filter (where priority = 'critical'),
        'high', count(*) filter (where priority = 'high'),
        'medium', count(*) filter (where priority = 'medium'),
        'low', count(*) filter (where priority = 'low')
      )
      from public.alarms
      where station_id = p_station_id and status in ('active', 'acknowledged')
    ),
    'device_status_summary', (
      select json_build_object(
        'total', count(*),
        'online', count(*) filter (where is_online),
        'offline', count(*) filter (where not is_online)
      )
      from public.device_health_view
      where station_id = p_station_id
    ),
    'period_hours', p_period_hours,
    'generated_at', now()
  ) into result;

  return result;
end;
$$;

comment on function public.get_station_kpi is 'Mengembalikan ringkasan KPI terkini satu stasiun dalam JSON';

-- get_trend_data: time-bucket agregasi nilai sensor
create or replace function public.get_trend_data(
  p_tag_id text,
  p_from_ts timestamptz,
  p_to_ts timestamptz,
  p_interval_minutes integer default 5
)
returns table (
  bucket timestamptz,
  avg_value float8,
  min_value float8,
  max_value float8,
  sample_count bigint
)
language sql
stable
as $$
  select
    to_timestamp(floor(extract(epoch from m.source_timestamp) / (p_interval_minutes * 60)) * (p_interval_minutes * 60)) as bucket,
    avg(m.value) as avg_value,
    min(m.value) as min_value,
    max(m.value) as max_value,
    count(*) as sample_count
  from public.measurements m
  where m.tag_id = p_tag_id
    and m.source_timestamp >= p_from_ts
    and m.source_timestamp <= p_to_ts
    and m.quality = 'good'
  group by bucket
  order by bucket asc;
$$;

comment on function public.get_trend_data is 'Agregasi time-bucket nilai sensor untuk grafik trend';

-- get_alarm_statistics: jumlah alarm per prioritas, tipe, dan hari
create or replace function public.get_alarm_statistics(p_station_id uuid, p_days integer default 30)
returns json
language plpgsql
stable
as $$
declare
  result json;
begin
  select json_build_object(
    'by_priority', (
      select json_object_agg(priority, cnt) from (
        select priority, count(*) as cnt
        from public.alarms
        where station_id = p_station_id
          and active_at >= now() - (p_days || ' days')::interval
        group by priority
      ) s
    ),
    'by_type', (
      select json_object_agg(alarm_type, cnt) from (
        select alarm_type, count(*) as cnt
        from public.alarms
        where station_id = p_station_id
          and active_at >= now() - (p_days || ' days')::interval
        group by alarm_type
      ) s
    ),
    'by_day', (
      select json_agg(row_to_json(s)) from (
        select date_trunc('day', active_at)::date as day, count(*) as cnt
        from public.alarms
        where station_id = p_station_id
          and active_at >= now() - (p_days || ' days')::interval
        group by date_trunc('day', active_at)::date
        order by day asc
      ) s
    ),
    'avg_resolve_seconds_by_priority', (
      select json_object_agg(priority, avg_sec) from (
        select priority, round(avg(extract(epoch from (cleared_at - active_at)))) as avg_sec
        from public.alarms
        where station_id = p_station_id
          and active_at >= now() - (p_days || ' days')::interval
          and cleared_at is not null
        group by priority
      ) s
    ),
    'total_alarms', (
      select count(*) from public.alarms
      where station_id = p_station_id
        and active_at >= now() - (p_days || ' days')::interval
    )
  ) into result;

  return result;
end;
$$;

comment on function public.get_alarm_statistics is 'Statistik alarm per prioritas, tipe, dan hari';

-- acknowledge_alarm: update status alarm + catat event
create or replace function public.acknowledge_alarm(p_alarm_id uuid, p_comment text default null)
returns public.alarms
language plpgsql
security definer
set search_path = public
as $$
declare
  v_alarm public.alarms;
  v_actor_id uuid := auth.uid();
  v_actor_email text;
  v_actor_role text;
begin
  if v_actor_id is null then
    raise exception 'Autentikasi diperlukan';
  end if;
  if not public.has_min_role('technician') then
    raise exception 'Role tidak memiliki izin acknowledge alarm';
  end if;

  select email into v_actor_email from auth.users where id = v_actor_id;
  select role into v_actor_role from public.profiles where id = v_actor_id;

  if not exists (
    select 1 from public.alarms a
    where a.id = p_alarm_id and public.current_user_can_access_station(a.station_id)
  ) then
    raise exception 'Alarm tidak ditemukan atau stasiun tidak dapat diakses';
  end if;

  update public.alarms
  set status = 'acknowledged',
      acknowledged_at = now(),
      acknowledged_by = v_actor_id,
      ack_comment = p_comment
  where id = p_alarm_id and status = 'active'
  returning * into v_alarm;

  if v_alarm.id is null then
    raise exception 'Alarm tidak ditemukan atau sudah tidak aktif';
  end if;

  insert into public.events (
    station_id, event_type, severity, message, actor_id, actor_email, actor_role, tag_id, metadata
  ) values (
    v_alarm.station_id, 'alarm_ack', 'info',
    format('Alarm diakui: %s', v_alarm.message),
    v_actor_id, v_actor_email, v_actor_role, v_alarm.tag_id,
    jsonb_build_object('alarm_id', v_alarm.id, 'comment', p_comment)
  );

  return v_alarm;
end;
$$;

comment on function public.acknowledge_alarm is 'Mengakui (acknowledge) alarm aktif dan mencatat event terkait';

create or replace function public.send_command(
  p_station_id uuid,
  p_device_id uuid default null,
  p_tag_id text default null,
  p_command_type text default null,
  p_value text default null
)
returns public.commands
language plpgsql
security definer
set search_path = public
as $$
declare
  v_command public.commands;
begin
  if auth.uid() is null then raise exception 'Autentikasi diperlukan'; end if;
  if not public.has_min_role('operator') then raise exception 'Role tidak memiliki izin mengirim command'; end if;
  if p_station_id is null or not public.current_user_can_access_station(p_station_id) then
    raise exception 'Stasiun tidak dapat diakses';
  end if;
  if p_device_id is not null and not exists (
    select 1 from public.devices where id = p_device_id and station_id = p_station_id
  ) then raise exception 'Device tidak sesuai stasiun'; end if;
  if p_tag_id is not null and not exists (
    select 1 from public.tags where tag_id = p_tag_id and station_id = p_station_id
  ) then raise exception 'Tag tidak sesuai stasiun'; end if;
  if p_command_type is null or p_command_type not in (
    'start', 'stop', 'reset', 'setpoint', 'open', 'close', 'acknowledge',
    'mode_change', 'write_tag', 'restart_device', 'enable_device',
    'disable_device', 'ack_all_alarms'
  ) then raise exception 'Tipe command tidak valid'; end if;

  insert into public.commands (station_id, device_id, tag_id, command_type, value, requested_by)
  values (p_station_id, p_device_id, p_tag_id, p_command_type, p_value, auth.uid())
  returning * into v_command;
  return v_command;
end;
$$;

comment on function public.send_command is 'Membuat command tervalidasi dengan actor dari auth.uid()';

-- ----------------------------------------------------------------------------
-- 14. TRIGGER FUNCTIONS
-- ----------------------------------------------------------------------------

-- 14.1 Auto-update updated_at
create or replace function public.trg_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_updated_at_stations on public.stations;
create trigger set_updated_at_stations
  before update on public.stations
  for each row execute function public.trg_set_updated_at();

drop trigger if exists set_updated_at_devices on public.devices;
create trigger set_updated_at_devices
  before update on public.devices
  for each row execute function public.trg_set_updated_at();

drop trigger if exists set_updated_at_profiles on public.profiles;
create trigger set_updated_at_profiles
  before update on public.profiles
  for each row execute function public.trg_set_updated_at();

-- 14.2 Threshold check pada INSERT measurements -> buat alarm otomatis.
-- Deadband dipakai saat CLEAR, bukan saat ACTIVATE: alarm high baru aktif pada
-- threshold asli, tetapi baru clear setelah nilai turun threshold - deadband.
create or replace function public.trg_check_measurement_threshold()
returns trigger
language plpgsql
as $$
declare
  v_tag public.tags;
  v_alarm record;
  v_priority text;
  v_type text;
  v_threshold float8;
  v_hold boolean := false;
  v_existing boolean := false;
  v_recovered boolean;
  v_rank integer;
  v_existing_rank integer;
begin
  select * into v_tag
  from public.tags
  where tag_id = new.tag_id and station_id = new.station_id;

  if v_tag.id is null or new.value is null then
    return new;
  end if;

  -- Quality buruk/stale tidak boleh mengubah state threshold. Alarm stale
  -- dibuat oleh run_alarm_engine karena freshness hanya diketahui terhadap now().
  if new.quality <> 'good' then
    return new;
  end if;

  -- Tentukan pelanggaran dengan prioritas tertinggi (aktivasi tanpa deadband).
  if v_tag.alarm_high_high is not null and new.value >= v_tag.alarm_high_high then
    v_type := 'high_high'; v_priority := 'critical'; v_threshold := v_tag.alarm_high_high; v_rank := 2;
  elsif v_tag.alarm_low_low is not null and new.value <= v_tag.alarm_low_low then
    v_type := 'low_low'; v_priority := 'critical'; v_threshold := v_tag.alarm_low_low; v_rank := 2;
  elsif v_tag.alarm_high is not null and new.value >= v_tag.alarm_high then
    v_type := 'high'; v_priority := 'high'; v_threshold := v_tag.alarm_high; v_rank := 1;
  elsif v_tag.alarm_low is not null and new.value <= v_tag.alarm_low then
    v_type := 'low'; v_priority := 'high'; v_threshold := v_tag.alarm_low; v_rank := 1;
  end if;

  -- Pertahankan alarm sampai recovery threshold (hysteresis). Alarm level
  -- lebih tinggi yang belum pulih menahan alarm level yang lebih rendah.
  for v_alarm in
    select id, alarm_type from public.alarms
    where station_id = new.station_id and tag_id = new.tag_id
      and alarm_type in ('high_high', 'high', 'low', 'low_low')
      and status in ('active', 'acknowledged')
  loop
    v_recovered := case v_alarm.alarm_type
      when 'high_high' then v_tag.alarm_high_high is null or new.value < v_tag.alarm_high_high - coalesce(v_tag.deadband, 0)
      when 'high' then v_tag.alarm_high is null or new.value < v_tag.alarm_high - coalesce(v_tag.deadband, 0)
      when 'low_low' then v_tag.alarm_low_low is null or new.value > v_tag.alarm_low_low + coalesce(v_tag.deadband, 0)
      when 'low' then v_tag.alarm_low is null or new.value > v_tag.alarm_low + coalesce(v_tag.deadband, 0)
      else true
    end;
    v_existing_rank := case when v_alarm.alarm_type in ('high_high', 'low_low') then 2 else 1 end;

    if v_alarm.alarm_type = v_type then
      if v_recovered then
        update public.alarms
        set status = 'cleared', cleared_at = now(),
            duration_seconds = extract(epoch from (now() - active_at))::integer
        where id = v_alarm.id;
      else
        v_existing := true;
        v_hold := true;
      end if;
    elsif not v_recovered and (v_type is null or v_existing_rank > v_rank) then
      v_hold := true;
    elsif v_recovered or (v_type is not null and v_rank > v_existing_rank) then
      update public.alarms
      set status = 'cleared', cleared_at = now(),
          duration_seconds = extract(epoch from (now() - active_at))::integer
      where id = v_alarm.id;
    end if;
  end loop;

  if v_hold or v_existing or v_type is null then
    return new;
  end if;

  insert into public.alarms (
    station_id, tag_id, alarm_type, priority, message, value_at_alarm, threshold_value
  ) values (
    new.station_id, new.tag_id, v_type, v_priority,
    format('%s %s: nilai %s melewati batas %s (%s)', v_tag.name, v_type, new.value, v_threshold, v_tag.unit),
    new.value, v_threshold
  );

  return new;
end;
$$;

drop trigger if exists check_measurement_threshold on public.measurements;
create trigger check_measurement_threshold
  after insert on public.measurements
  for each row execute function public.trg_check_measurement_threshold();

-- 14.3 Evaluator terjadwal untuk kondisi yang tidak bisa dideteksi hanya dari
-- INSERT measurement: data stale dan device offline. Frontend/cron memanggil
-- fungsi ini berkala; advisory lock membuat dua evaluator tidak menggandakan alarm.
create or replace function public.run_alarm_engine(p_station_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tag record;
  v_device record;
  v_latest record;
  v_existing_id uuid;
  v_scan_seconds integer;
  v_stale_after integer;
  v_is_stale boolean;
  v_has_latest boolean;
  v_is_offline boolean;
  v_created integer := 0;
  v_cleared integer := 0;
begin
  if auth.uid() is null
     and coalesce(current_setting('request.jwt.claim.role', true), '') <> 'service_role' then
    raise exception 'Autentikasi diperlukan';
  end if;
  if auth.uid() is not null and not public.current_user_can_access_station(p_station_id) then
    raise exception 'Stasiun tidak dapat diakses';
  end if;

  perform pg_advisory_xact_lock(hashtext('river-flow-alarm-engine:' || p_station_id::text));

  -- Satu data-stale alarm per tag. Device maintenance/nonaktif tidak dipaksa
  -- menghasilkan alarm telemetry karena memang sengaja tidak dipolling.
  for v_tag in
    select t.tag_id, t.name, t.unit, t.device_id
    from public.tags t
    left join public.devices d on d.id = t.device_id
    where t.station_id = p_station_id and t.enabled
      and (d.id is null or d.enabled)
  loop
    select m.quality, m.source_timestamp
      into v_latest
    from public.measurements m
    where m.station_id = p_station_id and m.tag_id = v_tag.tag_id
    order by m.source_timestamp desc, m.received_timestamp desc
    limit 1;

    v_has_latest := found;

    select greatest(coalesce(d.scan_interval_sec, 10) * 3, 30)
      into v_stale_after
    from public.devices d
    where d.id = v_tag.device_id;
    v_stale_after := coalesce(v_stale_after, 60);

    v_is_stale := not v_has_latest
      or v_latest.source_timestamp is null
      or v_latest.quality <> 'good'
      or extract(epoch from (now() - v_latest.source_timestamp)) > v_stale_after;

    select id into v_existing_id
    from public.alarms
    where station_id = p_station_id and tag_id = v_tag.tag_id
      and alarm_type = 'data_stale' and status in ('active', 'acknowledged')
    limit 1;

    if v_is_stale and v_existing_id is null then
      insert into public.alarms (
        station_id, tag_id, alarm_type, priority, message, threshold_value
      ) values (
        p_station_id, v_tag.tag_id, 'data_stale', 'high',
        format('%s stale: tidak ada telemetry GOOD dalam %s detik terakhir', v_tag.name, v_stale_after),
        v_stale_after
      );
      v_created := v_created + 1;
    elsif not v_is_stale and v_existing_id is not null then
      update public.alarms
      set status = 'cleared', cleared_at = now(),
          duration_seconds = extract(epoch from (now() - active_at))::integer
      where id = v_existing_id;
      v_cleared := v_cleared + 1;
    end if;
  end loop;

  -- Device offline ditentukan dari status dan last_seen, bukan dari koneksi
  -- browser. Maintenance/nonaktif dikecualikan agar tidak menimbulkan noise.
  for v_device in
    select d.id, d.name, d.status, d.last_seen, d.scan_interval_sec
    from public.devices d
    where d.station_id = p_station_id and d.enabled and d.status <> 'maintenance'
  loop
    v_is_offline := v_device.status in ('offline', 'error')
      or v_device.last_seen is null
      or extract(epoch from (now() - v_device.last_seen)) > greatest(v_device.scan_interval_sec * 3, 30);

    select id into v_existing_id
    from public.alarms
    where station_id = p_station_id and device_id = v_device.id
      and alarm_type = 'device_offline' and status in ('active', 'acknowledged')
    limit 1;

    if v_is_offline and v_existing_id is null then
      insert into public.alarms (
        station_id, device_id, alarm_type, priority, message
      ) values (
        p_station_id, v_device.id, 'device_offline', 'high',
        format('Device %s offline (%s)', v_device.name, v_device.status)
      );
      v_created := v_created + 1;
    elsif not v_is_offline and v_existing_id is not null then
      update public.alarms
      set status = 'cleared', cleared_at = now(),
          duration_seconds = extract(epoch from (now() - active_at))::integer
      where id = v_existing_id;
      v_cleared := v_cleared + 1;
    end if;
  end loop;

  return jsonb_build_object('station_id', p_station_id, 'created', v_created, 'cleared', v_cleared, 'evaluated_at', now());
end;
$$;

comment on function public.run_alarm_engine is 'Evaluasi hysteresis-independent untuk data stale dan device offline';
grant execute on function public.run_alarm_engine(uuid) to authenticated;

-- Dipakai oleh scheduler (pg_cron/worker service_role) agar offline detection
-- tetap berjalan walaupun tidak ada dashboard yang sedang terbuka.
create or replace function public.run_alarm_engine_all_stations()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_station record;
  v_count integer := 0;
begin
  -- pg_cron/worker memanggil fungsi ini tanpa JWT user; tandai konteks
  -- internal sebelum memanggil evaluator yang juga dapat dipanggil frontend.
  perform set_config('request.jwt.claim.role', 'service_role', true);
  for v_station in select id from public.stations where status <> 'inactive' loop
    perform public.run_alarm_engine(v_station.id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

comment on function public.run_alarm_engine_all_stations is 'Jalankan alarm engine untuk semua stasiun aktif; panggil tiap 15 detik dari scheduler tepercaya';
revoke all on function public.run_alarm_engine_all_stations() from public;
grant execute on function public.run_alarm_engine_all_stations() to service_role;

-- Contoh jadwal (aktifkan hanya jika pg_cron tersedia di project):
-- select cron.schedule('river-flow-alarm-engine', '*/1 * * * *',
--   $$select public.run_alarm_engine_all_stations()$$);

-- 14.4 Audit UPDATE profiles -> catat di events
create or replace function public.trg_audit_profile_update()
returns trigger
language plpgsql
as $$
declare
  v_actor_email text;
begin
  select email into v_actor_email from auth.users where id = auth.uid();

  if old.role is distinct from new.role or old.is_active is distinct from new.is_active then
    insert into public.events (
      event_type, severity, message, actor_id, actor_email, old_value, new_value, metadata
    ) values (
      'user_change', 'warning',
      format('Profil %s diubah', new.id),
      auth.uid(), v_actor_email,
      format('role=%s,active=%s', old.role, old.is_active),
      format('role=%s,active=%s', new.role, new.is_active),
      jsonb_build_object('profile_id', new.id)
    );
  end if;

  return new;
end;
$$;

drop trigger if exists audit_profile_update on public.profiles;
create trigger audit_profile_update
  after update on public.profiles
  for each row execute function public.trg_audit_profile_update();

-- 14.5 Audit UPDATE device status -> catat di events
create or replace function public.trg_audit_device_status()
returns trigger
language plpgsql
as $$
begin
  if old.status is distinct from new.status then
    insert into public.events (
      station_id, event_type, severity, message, device_id, old_value, new_value, metadata
    ) values (
      new.station_id, 'device_change',
      case when new.status in ('offline', 'error') then 'critical' else 'info' end,
      format('Status device %s berubah dari %s ke %s', new.name, old.status, new.status),
      new.id, old.status, new.status,
      jsonb_build_object('device_id', new.id)
    );

    -- Buat satu alarm device_offline per device. Evaluasi last_seen dilakukan
    -- oleh run_alarm_engine; trigger ini hanya mempercepat transisi eksplisit.
    if new.status in ('offline', 'error') then
      if not exists (
        select 1 from public.alarms
        where station_id = new.station_id and device_id = new.id
          and alarm_type = 'device_offline' and status in ('active', 'acknowledged')
      ) then
        insert into public.alarms (
          station_id, device_id, alarm_type, priority, message
        ) values (
          new.station_id, new.id, 'device_offline', 'high',
          format('Device %s menjadi %s', new.name, new.status)
        );
      end if;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists audit_device_status on public.devices;
create trigger audit_device_status
  after update on public.devices
  for each row execute function public.trg_audit_device_status();

-- ----------------------------------------------------------------------------
-- 15. RLS HELPER FUNCTIONS
-- ----------------------------------------------------------------------------
-- security definer agar tidak terjadi recursive RLS saat membaca profiles sendiri.

create or replace function public.current_user_role()
returns text
language sql
security definer
set search_path = public
stable
as $$
  select role from public.profiles where id = auth.uid();
$$;

create or replace function public.has_min_role(p_min_role text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select case
    when public.current_user_role() is null then false
    else (
      array_position(
        array['viewer', 'technician', 'operator', 'admin', 'superadmin'],
        public.current_user_role()
      ) >= array_position(
        array['viewer', 'technician', 'operator', 'admin', 'superadmin'],
        p_min_role
      )
    )
  end;
$$;

create or replace function public.current_user_can_access_station(p_station_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select p_station_id is not null and auth.uid() is not null and exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.is_active
      and (p.role = 'superadmin' or p_station_id = any(p.station_access))
  );
$$;

comment on function public.has_min_role is 'Cek apakah role user saat ini >= role minimum (hierarchy: viewer<technician<operator<admin<superadmin)';

-- ----------------------------------------------------------------------------
-- 16. ROW LEVEL SECURITY
-- ----------------------------------------------------------------------------

alter table public.stations enable row level security;
alter table public.devices enable row level security;
alter table public.tags enable row level security;
alter table public.measurements enable row level security;
alter table public.alarms enable row level security;
alter table public.events enable row level security;
alter table public.commands enable row level security;
alter table public.profiles enable row level security;
alter table public.monthly_reports enable row level security;
alter table public.breakdown_reports enable row level security;

-- ---- stations ----
drop policy if exists stations_select on public.stations;
create policy stations_select on public.stations
  for select to authenticated using (public.current_user_can_access_station(id));

drop policy if exists stations_insert on public.stations;
create policy stations_insert on public.stations
  for insert to authenticated with check (public.has_min_role('admin'));

drop policy if exists stations_update on public.stations;
create policy stations_update on public.stations
  for update to authenticated using (public.has_min_role('admin') and public.current_user_can_access_station(id));

drop policy if exists stations_delete on public.stations;
create policy stations_delete on public.stations
  for delete to authenticated using (public.has_min_role('superadmin') and public.current_user_can_access_station(id));

-- ---- devices ----
drop policy if exists devices_select on public.devices;
create policy devices_select on public.devices
  for select to authenticated using (public.current_user_can_access_station(station_id));

drop policy if exists devices_cud on public.devices;
create policy devices_insert on public.devices
  for insert to authenticated with check (public.has_min_role('admin') and public.current_user_can_access_station(station_id));
create policy devices_update on public.devices
  for update to authenticated using (public.has_min_role('admin') and public.current_user_can_access_station(station_id));
create policy devices_delete on public.devices
  for delete to authenticated using (public.has_min_role('superadmin') and public.current_user_can_access_station(station_id));

-- ---- tags ----
drop policy if exists tags_select on public.tags;
create policy tags_select on public.tags
  for select to authenticated using (public.current_user_can_access_station(station_id));

create policy tags_insert on public.tags
  for insert to authenticated with check (public.has_min_role('admin') and public.current_user_can_access_station(station_id));
create policy tags_update on public.tags
  for update to authenticated using (public.has_min_role('admin') and public.current_user_can_access_station(station_id));
create policy tags_delete on public.tags
  for delete to authenticated using (public.has_min_role('superadmin'));

-- ---- measurements ----
drop policy if exists measurements_select on public.measurements;
create policy measurements_select on public.measurements
  for select to authenticated using (public.current_user_can_access_station(station_id));

drop policy if exists measurements_insert on public.measurements;
create policy measurements_insert on public.measurements
  for insert to authenticated with check (public.has_min_role('operator') and public.current_user_can_access_station(station_id));

drop policy if exists measurements_update on public.measurements;
create policy measurements_update on public.measurements
  for update to authenticated using (public.has_min_role('admin') and public.current_user_can_access_station(station_id));

drop policy if exists measurements_delete on public.measurements;
create policy measurements_delete on public.measurements
  for delete to authenticated using (public.has_min_role('admin') and public.current_user_can_access_station(station_id));

-- ---- alarms ----
drop policy if exists alarms_select on public.alarms;
create policy alarms_select on public.alarms
  for select to authenticated using (public.current_user_can_access_station(station_id));

drop policy if exists alarms_insert on public.alarms;
create policy alarms_insert on public.alarms
  for insert to authenticated with check (public.has_min_role('operator') and public.current_user_can_access_station(station_id));

drop policy if exists alarms_update on public.alarms;
create policy alarms_update on public.alarms
  for update to authenticated using (public.has_min_role('technician') and public.current_user_can_access_station(station_id));

drop policy if exists alarms_delete on public.alarms;
create policy alarms_delete on public.alarms
  for delete to authenticated using (public.has_min_role('admin') and public.current_user_can_access_station(station_id));

-- ---- events ----
drop policy if exists events_select on public.events;
create policy events_select on public.events
  for select to authenticated using (public.current_user_can_access_station(station_id));

drop policy if exists events_insert on public.events;
create policy events_insert on public.events
  for insert to authenticated with check (
    (station_id is null and actor_id = auth.uid())
    or (public.has_min_role('operator') and public.current_user_can_access_station(station_id))
  );

-- Events bersifat immutable: tidak ada policy update/delete untuk authenticated
-- (hanya service_role via bypass RLS yang dapat melakukannya jika benar-benar perlu).

-- ---- profiles ----
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated using (id = auth.uid() or public.has_min_role('admin'));

drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles
  for update to authenticated
  using (id = auth.uid() or public.has_min_role('superadmin'));

drop policy if exists profiles_insert on public.profiles;
create policy profiles_insert on public.profiles
  for insert to authenticated
  with check (id = auth.uid() or public.has_min_role('admin'));

drop policy if exists profiles_delete on public.profiles;
create policy profiles_delete on public.profiles
  for delete to authenticated using (public.has_min_role('superadmin'));

-- ---- commands ----
drop policy if exists commands_select on public.commands;
create policy commands_select on public.commands
  for select to authenticated using (public.has_min_role('operator') and public.current_user_can_access_station(station_id));

drop policy if exists commands_insert on public.commands;
create policy commands_insert on public.commands
  for insert to authenticated with check (false);

drop policy if exists commands_update on public.commands;
create policy commands_update on public.commands
  for update to authenticated using (public.has_min_role('admin') and public.current_user_can_access_station(station_id));

-- ---- monthly_reports ----
drop policy if exists monthly_reports_select on public.monthly_reports;
create policy monthly_reports_select on public.monthly_reports
  for select to authenticated using (public.current_user_can_access_station(station_id));

create policy monthly_reports_insert on public.monthly_reports
  for insert to authenticated with check (public.has_min_role('operator') and public.current_user_can_access_station(station_id));
create policy monthly_reports_update on public.monthly_reports
  for update to authenticated using (public.has_min_role('admin') and public.current_user_can_access_station(station_id));
create policy monthly_reports_delete on public.monthly_reports
  for delete to authenticated using (public.has_min_role('superadmin') and public.current_user_can_access_station(station_id));

-- ---- breakdown_reports ----
drop policy if exists breakdown_reports_select on public.breakdown_reports;
create policy breakdown_reports_select on public.breakdown_reports
  for select to authenticated using (public.current_user_can_access_station(station_id));

create policy breakdown_reports_insert on public.breakdown_reports
  for insert to authenticated with check (public.has_min_role('operator') and public.current_user_can_access_station(station_id));
create policy breakdown_reports_update on public.breakdown_reports
  for update to authenticated using (public.has_min_role('admin') and public.current_user_can_access_station(station_id));
create policy breakdown_reports_delete on public.breakdown_reports
  for delete to authenticated using (public.has_min_role('superadmin') and public.current_user_can_access_station(station_id));

-- ----------------------------------------------------------------------------
-- 17. REALTIME PUBLICATION
-- ----------------------------------------------------------------------------
-- Aktifkan replication untuk tabel yang perlu dipantau real-time di frontend.
alter publication supabase_realtime add table public.measurements;
alter publication supabase_realtime add table public.alarms;
alter publication supabase_realtime add table public.devices;

-- ----------------------------------------------------------------------------
-- 18. SEED DATA
-- ----------------------------------------------------------------------------

-- Station tetap (UUID fix agar bisa dirujuk dari .env VITE_STATION_ID)
insert into public.stations (id, name, location, river_name, latitude, longitude, status, description)
values (
  'aaaaaaaa-0001-0000-0000-000000000001',
  'Stasiun Sungai Kincang',
  'Banjarnegara, Jawa Tengah',
  'Kali Kincang',
  -7.3200, 109.7100,
  'active',
  'Stasiun pemantauan PLTMH dan hidrologi Kali Kincang'
)
on conflict (id) do nothing;

-- Devices
insert into public.devices (id, station_id, name, device_type, protocol, modbus_address, status, firmware_version, manufacturer, model)
values
  ('bbbbbbbb-0001-0000-0000-000000000001', 'aaaaaaaa-0001-0000-0000-000000000001', 'Radar Flow Meter', 'radar_flowmeter', 'modbus_rtu', 1, 'online', 'v2.1.0', 'OTT HydroMet', 'RLS-1000'),
  ('bbbbbbbb-0002-0000-0000-000000000001', 'aaaaaaaa-0001-0000-0000-000000000001', 'Power Meter', 'power_meter', 'modbus_rtu', 2, 'online', 'v1.5.2', 'Schneider', 'PM5110'),
  ('bbbbbbbb-0003-0000-0000-000000000001', 'aaaaaaaa-0001-0000-0000-000000000001', 'PLC Kontrol Turbin', 'plc', 'modbus_tcp', null, 'online', 'v3.0.1', 'Siemens', 'S7-1200'),
  ('bbbbbbbb-0004-0000-0000-000000000001', 'aaaaaaaa-0001-0000-0000-000000000001', 'Gateway 4G', 'gateway', 'mqtt', null, 'online', 'v1.0.4', 'Teltonika', 'RUT240')
on conflict (id) do nothing;

-- Tags
insert into public.tags (station_id, device_id, tag_id, name, unit, alarm_high, alarm_low, display_precision)
values
  ('aaaaaaaa-0001-0000-0000-000000000001', 'bbbbbbbb-0001-0000-0000-000000000001', 'HYDRO.WATER_LEVEL', 'Tinggi Muka Air', 'm', 2.5, 0.4, 2),
  ('aaaaaaaa-0001-0000-0000-000000000001', 'bbbbbbbb-0001-0000-0000-000000000001', 'HYDRO.VELOCITY', 'Kecepatan Aliran', 'm/s', null, null, 2),
  ('aaaaaaaa-0001-0000-0000-000000000001', 'bbbbbbbb-0001-0000-0000-000000000001', 'HYDRO.FLOW_RATE', 'Debit Aliran', 'm3/s', null, null, 3),
  ('aaaaaaaa-0001-0000-0000-000000000001', 'bbbbbbbb-0001-0000-0000-000000000001', 'HYDRO.CUMULATIVE_VOL', 'Volume Kumulatif', 'm3', null, null, 1),
  ('aaaaaaaa-0001-0000-0000-000000000001', 'bbbbbbbb-0001-0000-0000-000000000001', 'HYDRO.RADAR_TEMP', 'Suhu Sensor Radar', 'C', null, null, 1),
  ('aaaaaaaa-0001-0000-0000-000000000001', 'bbbbbbbb-0001-0000-0000-000000000001', 'HYDRO.ECHO_AMPLITUDE', 'Amplitudo Echo', 'dB', null, null, 1),
  ('aaaaaaaa-0001-0000-0000-000000000001', 'bbbbbbbb-0002-0000-0000-000000000001', 'POWER.ACTIVE_POWER', 'Daya Aktif', 'kW', 150, null, 2),
  ('aaaaaaaa-0001-0000-0000-000000000001', 'bbbbbbbb-0002-0000-0000-000000000001', 'POWER.REACTIVE_POWER', 'Daya Reaktif', 'kVAr', null, null, 2),
  ('aaaaaaaa-0001-0000-0000-000000000001', 'bbbbbbbb-0002-0000-0000-000000000001', 'POWER.VOLTAGE_L1', 'Tegangan L1', 'V', null, null, 1),
  ('aaaaaaaa-0001-0000-0000-000000000001', 'bbbbbbbb-0002-0000-0000-000000000001', 'POWER.CURRENT_L1', 'Arus L1', 'A', null, null, 2),
  ('aaaaaaaa-0001-0000-0000-000000000001', 'bbbbbbbb-0002-0000-0000-000000000001', 'POWER.FREQUENCY', 'Frekuensi', 'Hz', null, null, 2),
  ('aaaaaaaa-0001-0000-0000-000000000001', 'bbbbbbbb-0002-0000-0000-000000000001', 'POWER.ENERGY_KWH', 'Energi Kumulatif', 'kWh', null, null, 1),
  ('aaaaaaaa-0001-0000-0000-000000000001', 'bbbbbbbb-0002-0000-0000-000000000001', 'POWER.POWER_FACTOR', 'Faktor Daya', 'PF', null, null, 2),
  ('aaaaaaaa-0001-0000-0000-000000000001', 'bbbbbbbb-0003-0000-0000-000000000001', 'TURBINE.RPM', 'Putaran Turbin', 'rpm', 1600, null, 0),
  ('aaaaaaaa-0001-0000-0000-000000000001', 'bbbbbbbb-0003-0000-0000-000000000001', 'TURBINE.STATUS', 'Status Turbin', '-', null, null, 0),
  ('aaaaaaaa-0001-0000-0000-000000000001', 'bbbbbbbb-0003-0000-0000-000000000001', 'SYS.PLC_STATUS', 'Status PLC', '-', null, null, 0),
  ('aaaaaaaa-0001-0000-0000-000000000001', 'bbbbbbbb-0004-0000-0000-000000000001', 'SYS.GATEWAY_STATUS', 'Status Gateway', '-', null, null, 0),
  ('aaaaaaaa-0001-0000-0000-000000000001', 'bbbbbbbb-0004-0000-0000-000000000001', 'SYS.BATTERY_VOLTAGE', 'Tegangan Baterai', 'V', null, 11, 2),
  ('aaaaaaaa-0001-0000-0000-000000000001', 'bbbbbbbb-0004-0000-0000-000000000001', 'SYS.SIGNAL_STRENGTH', 'Kekuatan Sinyal', 'dBm', null, null, 0)
on conflict (tag_id) do nothing;

-- Nilai awal yang tersimpan di database. Gateway dapat menggantinya dengan
-- measurement lapangan berikutnya tanpa perubahan pada aplikasi.
with seed(tag_id, value) as (
  values
    ('HYDRO.WATER_LEVEL', 1.45),
    ('HYDRO.VELOCITY', 1.10),
    ('HYDRO.FLOW_RATE', 3.20),
    ('POWER.ACTIVE_POWER', 50.00),
    ('POWER.ENERGY_KWH', 123456.70),
    ('TURBINE.RPM', 1250.00),
    ('SYS.BATTERY_VOLTAGE', 12.80),
    ('SYS.SIGNAL_STRENGTH', -72.00)
), stamped as (
  select tag_id, value, date_trunc('hour', now()) as source_timestamp from seed
)
insert into public.measurements (tag_id, station_id, value, quality, source_timestamp)
select s.tag_id, 'aaaaaaaa-0001-0000-0000-000000000001', s.value, 'good', s.source_timestamp
from stamped s
where not exists (
  select 1 from public.measurements m
  where m.tag_id = s.tag_id
    and m.station_id = 'aaaaaaaa-0001-0000-0000-000000000001'
    and m.source_timestamp = s.source_timestamp
);

-- ----------------------------------------------------------------------------
-- SELESAI
-- ----------------------------------------------------------------------------
-- Catatan:
-- 1. Setelah menjalankan schema ini, buat user pertama melalui Supabase Auth
--    (Dashboard > Authentication > Add User), lalu insert row ke public.profiles
--    dengan role 'superadmin' agar bisa mengakses semua fitur.
-- 2. Jalankan public.create_measurements_partition(current_date) via pg_cron
--    setiap awal bulan untuk membuat partisi measurements bulan berikutnya.
-- 3. Edge Function untuk ingest data dari gateway fisik (Bagian 11 instruksi)
--    cukup melakukan INSERT ke public.measurements; trigger threshold akan
--    otomatis membuat alarm.
