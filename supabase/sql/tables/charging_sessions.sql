-- =============================================================================
-- Table: public.charging_sessions
-- -----------------------------------------------------------------------------
-- PURPOSE
--   One row per actual charging session (the "transaction" in OCPP terms).
--   Created when the driver taps Start Charging and the (mock) charger accepts
--   the RemoteStartTransaction; closed when charging stops.
--
-- RELATIONSHIPS
--   - reservation_id -> reservations(id)  ON DELETE CASCADE  (1-1, unique)
--   - Referenced by: session_streams.session_id, session_payments.session_id
--
-- INDEXES
--   - charging_sessions_status_idx on (status) – the mock charger tick and the
--     "charger in use" check both look for status = 'charging'.
--
-- TRIGGERS
--   - charging_sessions_set_updated_at: set_updated_at() BEFORE UPDATE.
--
-- NOTES
--   - transaction_id is the integer OCPP transactionId returned to the app and
--     carried in every MeterValues message.
--   - meter_start_wh / meter_stop_wh are the charger's energy register (Wh) at
--     start/stop, as in OCPP StartTransaction/StopTransaction.
--   - price_per_kwh_at_start locks the charger's price when charging begins, so
--     a host price change mid-session doesn't affect this session.
--   - status: 'charging' | 'completed'.
--   - stop_reason: 'user' | 'time_up' | 'battery_full' (null while charging).
--   - Writes happen only through the ocpp_* SQL functions (called by edge
--     functions with the service role). Drivers can only SELECT their own rows.
-- =============================================================================

create table public.charging_sessions (
  id uuid not null default gen_random_uuid (),
  reservation_id uuid not null,
  transaction_id bigint generated always as identity,
  price_per_kwh_at_start numeric(10, 2) not null,
  meter_start_wh bigint not null,
  meter_stop_wh bigint null,
  started_at timestamp with time zone not null default now(),
  ended_at timestamp with time zone null,
  total_energy_kwh numeric(10, 3) null,
  status character varying(20) not null default 'charging'::character varying,
  stop_reason character varying(20) null,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  constraint charging_sessions_pkey primary key (id),
  constraint charging_sessions_reservation_id_key unique (reservation_id),
  constraint charging_sessions_transaction_id_key unique (transaction_id),
  constraint charging_sessions_reservation_id_fkey foreign key (reservation_id)
    references reservations (id) on delete cascade,
  constraint charging_sessions_status_valid check (
    (status)::text = any (array['charging', 'completed']::text[])
  ),
  constraint charging_sessions_stop_reason_valid check (
    stop_reason is null
    or (stop_reason)::text = any (array['user', 'time_up', 'battery_full']::text[])
  )
) tablespace pg_default;

create index if not exists charging_sessions_status_idx
  on public.charging_sessions using btree (status) tablespace pg_default;

create trigger charging_sessions_set_updated_at before
update on charging_sessions for each row
execute function set_updated_at ();
