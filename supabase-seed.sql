-- Demo data untuk River Flow Guardian.
-- Jalankan setelah supabase-schema.sql di Supabase SQL Editor.
-- Aman dijalankan ulang: data demo memakai ID deterministik dan di-upsert.

insert into public.stations (id, name, location, latitude, longitude, description, status, river_name, installation_date, elevation_m)
values
  ('ce9ceebb-921b-4275-83f1-1679cff06d04', 'Stasiun Citarum 01', 'Bendung Citarum', -6.914744, 107.609810, 'Stasiun utama pemantauan sungai', 'active', 'Sungai Citarum', '2024-03-15', 48),
  ('ce9ceebb-921b-4275-83f1-1679cff06d05', 'Stasiun Citarum 02', 'Majalaya', -7.050500, 107.756700, 'Stasiun hulu', 'active', 'Sungai Citarum', '2024-04-02', 62),
  ('ce9ceebb-921b-4275-83f1-1679cff06d06', 'Stasiun Citarum 03', 'Rancaekek', -6.959700, 107.758400, 'Stasiun inspeksi berkala', 'maintenance', 'Sungai Citarum', '2024-05-11', 55),
  ('ce9ceebb-921b-4275-83f1-1679cff06d07', 'Stasiun Citarum 04', 'Bojongsoang', -6.982200, 107.630600, 'Stasiun tengah', 'active', 'Sungai Citarum', '2024-06-20', 49),
  ('ce9ceebb-921b-4275-83f1-1679cff06d08', 'Stasiun Citarum 05', 'Dayeuhkolot', -6.987700, 107.623100, 'Stasiun hilir', 'active', 'Sungai Citarum', '2024-07-08', 45),
  ('ce9ceebb-921b-4275-83f1-1679cff06d09', 'Stasiun Citarum 06', 'Sapan', -6.991600, 107.751200, 'Stasiun cadangan', 'inactive', 'Sungai Citarum', '2024-08-19', 51)
on conflict (id) do update set name = excluded.name, location = excluded.location, status = excluded.status, updated_at = now();

insert into public.devices (id, station_id, name, device_type, protocol, status, last_seen, scan_interval_sec, enabled, firmware_version, manufacturer, model)
select ('10000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid, s.id,
  case when n % 3 = 0 then 'Radar Flowmeter' when n % 3 = 1 then 'Gateway IoT' else 'Power Meter' end,
  case when n % 3 = 0 then 'radar_flowmeter' when n % 3 = 1 then 'gateway' else 'power_meter' end,
  case when n % 3 = 0 then 'modbus_tcp' when n % 3 = 1 then 'mqtt' else 'modbus_rtu' end,
  case when n = 7 then 'error' when n = 5 then 'offline' else 'online' end,
  case when n in (5, 7) then now() - interval '35 minutes' else now() end,
  5, true, 'v3.1.0', 'River Guardian', 'RG-' || n
from generate_series(1, 12) as g(n)
cross join lateral (select id from public.stations order by id offset ((n - 1) % 6) limit 1) s
on conflict (id) do update set station_id = excluded.station_id, status = excluded.status, last_seen = excluded.last_seen;

insert into public.tags (id, device_id, station_id, tag_id, name, description, value_type, unit, alarm_high, alarm_high_high, alarm_low, alarm_low_low, display_precision)
values
  ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'ce9ceebb-921b-4275-83f1-1679cff06d04', 'HYDRO.WATER_LEVEL', 'Muka Air', 'Ketinggian muka air sungai', 'float', 'm', 2, 2.5, 0.8, 0.5, 2),
  ('20000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001', 'ce9ceebb-921b-4275-83f1-1679cff06d04', 'HYDRO.VELOCITY', 'Kecepatan Aliran', 'Kecepatan aliran sungai', 'float', 'm/s', 1.8, 2.2, 0.3, 0.1, 2),
  ('20000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000001', 'ce9ceebb-921b-4275-83f1-1679cff06d04', 'HYDRO.FLOW_RATE', 'Debit Aliran', 'Debit aliran sungai', 'float', 'm3/s', 7.5, 9, 0.5, 0.2, 2),
  ('20000000-0000-4000-8000-000000000004', '10000000-0000-4000-8000-000000000003', 'ce9ceebb-921b-4275-83f1-1679cff06d04', 'POWER.ACTIVE_POWER', 'Daya Aktif', 'Daya aktif generator', 'float', 'kW', 80, 90, 5, 0, 2),
  ('20000000-0000-4000-8000-000000000005', '10000000-0000-4000-8000-000000000003', 'ce9ceebb-921b-4275-83f1-1679cff06d04', 'POWER.ENERGY_KWH', 'Energi Kumulatif', 'Energi kumulatif generator', 'float', 'kWh', null, null, null, null, 2),
  ('20000000-0000-4000-8000-000000000006', '10000000-0000-4000-8000-000000000003', 'ce9ceebb-921b-4275-83f1-1679cff06d04', 'TURBINE.RPM', 'Putaran Turbin', 'Kecepatan putar turbin', 'float', 'rpm', 1500, 1600, 800, 700, 0),
  ('20000000-0000-4000-8000-000000000007', '10000000-0000-4000-8000-000000000004', 'ce9ceebb-921b-4275-83f1-1679cff06d04', 'SYS.BATTERY_VOLTAGE', 'Tegangan Baterai', 'Tegangan baterai gateway', 'float', 'V', 14, 14.5, 11.5, 11, 2),
  ('20000000-0000-4000-8000-000000000008', '10000000-0000-4000-8000-000000000004', 'ce9ceebb-921b-4275-83f1-1679cff06d04', 'SYS.SIGNAL_STRENGTH', 'Kekuatan Sinyal', 'Kekuatan sinyal gateway', 'float', 'dBm', null, null, null, null, 1)
on conflict (tag_id) do update set name = excluded.name, unit = excluded.unit, alarm_high = excluded.alarm_high, alarm_high_high = excluded.alarm_high_high, alarm_low = excluded.alarm_low, alarm_low_low = excluded.alarm_low_low;

-- Pastikan partisi tersedia untuk 3 bulan terakhir.
do $$
declare i integer;
begin
  for i in 0..3 loop
    perform public.create_measurements_partition((current_date - (i || ' month')::interval)::date);
  end loop;
end $$;

-- 4.009 titik waktu x 8 tag = 32.072 measurement: 3 bulan (per jam),
-- dengan 7 hari terakhir dipadatkan menjadi interval 5 menit.
delete from public.measurements where id >= 900000000 and id < 901000000;
insert into public.measurements (id, tag_id, station_id, value, quality, source_timestamp, received_timestamp)
with measurement_points as (
  select n as seq, now() - ((2160 - n) * interval '1 hour') as source_timestamp from generate_series(0, 1992) as g(n)
  union all
  select 1993 + n, now() - ((2015 - n) * interval '5 minutes') from generate_series(0, 2015) as g(n)
)
select 900000000 + (p.seq * 10) + t.ord,
  t.tag_id, 'ce9ceebb-921b-4275-83f1-1679cff06d04',
  round((case
    when t.tag_id = 'POWER.ENERGY_KWH' then t.base + p.seq * 0.72 + sin(p.seq / 20.0) * 0.2
    when t.tag_id = 'SYS.SIGNAL_STRENGTH' then t.base + sin(p.seq / 8.0) * 4
    else t.base + sin(p.seq / 23.0) * t.base * 0.06 + sin(p.seq / 7.0) * t.base * 0.02
  end)::numeric, 3)::float8,
  'good', p.source_timestamp, p.source_timestamp
from measurement_points p
cross join (values
  (1, 'HYDRO.WATER_LEVEL', 1.45::float8), (2, 'HYDRO.VELOCITY', 1.10::float8),
  (3, 'HYDRO.FLOW_RATE', 3.20::float8), (4, 'POWER.ACTIVE_POWER', 50::float8),
  (5, 'POWER.ENERGY_KWH', 123456.7::float8), (6, 'TURBINE.RPM', 1250::float8),
  (7, 'SYS.BATTERY_VOLTAGE', 12.8::float8), (8, 'SYS.SIGNAL_STRENGTH', -72::float8)
) as t(ord, tag_id, base)
on conflict (id, source_timestamp) do update set value = excluded.value, received_timestamp = excluded.received_timestamp;

insert into public.alarms (id, station_id, tag_id, alarm_type, priority, message, value_at_alarm, threshold_value, status, active_at, acknowledged_at, cleared_at, duration_seconds)
select ('30000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid, 'ce9ceebb-921b-4275-83f1-1679cff06d04',
  case when n % 3 = 0 then 'HYDRO.WATER_LEVEL' when n % 3 = 1 then 'POWER.ACTIVE_POWER' else 'SYS.BATTERY_VOLTAGE' end,
  case when n % 2 = 0 then 'high' else 'low' end,
  case when n % 5 = 0 then 'critical' when n % 2 = 0 then 'high' else 'medium' end,
  'Riwayat alarm demo #' || n, 1.9 + n / 30.0, 2,
  case when n <= 3 then 'active' else 'cleared' end,
  now() - (n * interval '9 hours'),
  case when n > 3 then now() - (n * interval '9 hours') + interval '10 minutes' end,
  case when n > 3 then now() - (n * interval '9 hours') + interval '45 minutes' end,
  case when n > 3 then 2700 end
from generate_series(1, 240) as g(n)
on conflict (id) do nothing;

insert into public.events (id, station_id, event_type, severity, message, actor_email, actor_role, metadata, created_at)
select ('40000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid, 'ce9ceebb-921b-4275-83f1-1679cff06d04',
  case when n % 4 = 0 then 'alarm_ack' when n % 4 = 1 then 'device_change' when n % 4 = 2 then 'config_change' else 'system' end,
  case when n % 7 = 0 then 'warning' else 'info' end,
  'Aktivitas sistem demo #' || n, 'operator@demo.local', 'operator', jsonb_build_object('seed', true, 'sequence', n), now() - (n * interval '4 hours')
from generate_series(1, 216) as g(n)
on conflict (id) do nothing;

insert into public.breakdown_reports (id, station_id, event_date, outage_start, outage_end, duration_hours, load_at_outage_kw, energy_not_served_kwh, cause, cause_category, affected_devices, corrective_action, operator_name, technician_name, status)
select ('50000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
  (array['ce9ceebb-921b-4275-83f1-1679cff06d04','ce9ceebb-921b-4275-83f1-1679cff06d05','ce9ceebb-921b-4275-83f1-1679cff06d06','ce9ceebb-921b-4275-83f1-1679cff06d07','ce9ceebb-921b-4275-83f1-1679cff06d08','ce9ceebb-921b-4275-83f1-1679cff06d09']::uuid[])[((n - 1) % 6) + 1],
  current_date - n, now() - (n * interval '1 day'), case when n % 3 = 0 then null else now() - (n * interval '1 day') + interval '90 minutes' end,
  case when n % 3 = 0 then 1.5 else 0.75 end, 35 + n, 25 + n * 3,
  case when n % 3 = 0 then 'Gateway kehilangan koneksi' when n % 3 = 1 then 'Tegangan listrik tidak stabil' else 'Sensor perlu kalibrasi' end,
  case when n % 3 = 0 then 'communication' when n % 3 = 1 then 'electrical' else 'maintenance' end,
  array['Gateway IoT'], 'Pemeriksaan dan pemulihan perangkat lapangan', 'Demo Operator', 'Teknisi Lapangan',
  case when n % 3 = 0 then 'in_progress' else 'resolved' end
from generate_series(1, 90) as g(n)
on conflict (id) do nothing;

insert into public.monthly_reports (id, station_id, report_date, total_energy_kwh, avg_power_kw, max_power_kw, min_power_kw, operational_hours, avg_water_level_m, max_water_level_m, min_water_level_m, avg_flow_rate_m3s, max_flow_rate_m3s, availability_percent, capacity_factor_percent, total_alarms, critical_alarms, data_quality_percent, notes, is_auto_generated)
select ('60000000-0000-4000-8000-' || lpad((n + 1)::text, 12, '0'))::uuid, 'ce9ceebb-921b-4275-83f1-1679cff06d04', date_trunc('month', current_date - (n || ' months')::interval)::date, 18500 + n * 340, 48 + n, 82 + n, 12 + n / 2.0, 640 - n * 3, 1.4 + n / 100.0, 1.95 + n / 100.0, 0.9 + n / 100.0, 3.1 + n / 20.0, 7.2 + n / 20.0, 97.5 - n / 2.0, 61 + n / 3.0, 12 + n, 2 + n % 3, 99 - n / 3.0, 'Laporan demo untuk pengujian dashboard', true
from generate_series(0, 11) as g(n)
on conflict (id) do nothing;