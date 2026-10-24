-- =============================================================================
-- Table: public.session_streams
-- -----------------------------------------------------------------------------
-- PURPOSE
--   Insert-only log of meter readings for a charging session. Each row is one
--   OCPP MeterValues sample reported by the (mock) charger, roughly every 30s,
--   plus the first reading at start and a final reading at stop.
--
-- RELATIONSHIPS
--   - session_id -> charging_sessions(id)  ON DELETE CASCADE
--
-- INDEXES
--   - session_streams_session_time_idx on (session_id, created_at desc) – the
--     app and the mock charger both read "latest reading for a session".
--
-- NOTES
--   - total_energy_received_kwh is cumulative since the session started
--     (charger register minus meter_start_wh), not the delta for this sample.
--   - soc_percent is the vehicle battery state of charge (0-100).
--   - Published to Realtime so the app receives new readings as they're
--     inserted (see supabase/policies/charging_policies.sql).
-- =============================================================================

create table public.session_streams (
  id uuid not null default gen_random_uuid (),
  session_id uuid not null,
  soc_percent numeric(5, 2) not null,
  power_kw numeric(10, 3) not null,
  total_energy_received_kwh numeric(10, 3) not null,
  created_at timestamp with time zone not null default now(),
  constraint session_streams_pkey primary key (id),
  constraint session_streams_session_id_fkey foreign key (session_id)
    references charging_sessions (id) on delete cascade,
  constraint session_streams_soc_valid check (
    soc_percent >= 0 and soc_percent <= 100
  ),
  constraint session_streams_power_valid check (power_kw >= 0),
  constraint session_streams_energy_valid check (total_energy_received_kwh >= 0)
) tablespace pg_default;

create index if not exists session_streams_session_time_idx
  on public.session_streams using btree (session_id, created_at desc)
  tablespace pg_default;
