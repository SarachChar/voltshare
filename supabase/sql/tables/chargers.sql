-- =============================================================================
-- Table: public.chargers
-- -----------------------------------------------------------------------------
-- PURPOSE
--   One charging unit inside a station: hardware specs, pricing and approval
--   status. Location, owner, photos, businesses and promotions live on the
--   station (see stations.sql). Referenced by charger_availability and
--   reservations.
--
-- RELATIONSHIPS
--   - station_id -> stations(id)  ON DELETE CASCADE  (required)
--   - Ownership = the station's host (stations.host_id); RLS checks it there.
--
-- INDEXES
--   - chargers_station_status_connector_idx on (station_id, status,
--     connector_type): the station search filters and per-station lookups.
--
-- TRIGGERS
--   - chargers_set_updated_at: set_updated_at() BEFORE UPDATE.
--
-- NOTES
--   - name is the unit's label inside its station, e.g. "Charger 1".
--   - status: review, setup, available, unavailable, rejected (check
--     constraint). The app creates chargers in 'review'; 'available' /
--     'unavailable' = live (the host can toggle; specs are locked in the app).
--   - price_per_kwh and power_kw are numeric(10,2).
--   - mock_error_code: TEST SWITCH for the mock charger (ocpp-status edge
--     function). Null = connector Available; an OCPP errorCode (e.g.
--     'GroundFailure') = Unavailable, so "I've Plugged In" cancels the booking
--     and refunds its fee (refund_booking_fee). Not read by the app.
--       update chargers set mock_error_code = 'GroundFailure' where id = '<uuid>';
--       update chargers set mock_error_code = null            where id = '<uuid>';
--   - RLS: enabled in policies/rls.sql; policies in policies/policies.sql.
--
-- HOW TO RUN (fresh project)
--   After profiles.sql and stations.sql (station_id references stations).
--   The live project reached this shape through sql/migrations/001 and 002.
-- =============================================================================

create table public.chargers (
  id uuid not null default gen_random_uuid (),
  station_id uuid not null,
  name character varying not null,
  charger_type character varying null,
  connector_type character varying null,
  power_kw numeric(10, 2) null,
  price_per_kwh numeric(10, 2) null,
  status character varying not null default 'available'::character varying,
  mock_error_code character varying(40) null,
  created_at timestamp with time zone null default now(),
  updated_at timestamp with time zone null default now(),
  constraint chargers_pkey primary key (id),
  constraint chargers_station_id_fkey foreign key (station_id)
    references stations (id) on delete cascade,
  constraint chargers_status_check check (
    (status)::text = any (
      array['review', 'setup', 'available', 'unavailable', 'rejected']::text[]
    )
  ),
  constraint chargers_mock_error_code_valid check (
    mock_error_code is null
    or (mock_error_code)::text = any (array[
      'ConnectorLockFailure', 'EVCommunicationError', 'GroundFailure',
      'HighTemperature', 'InternalError', 'LocalListConflict', 'OtherError',
      'OverCurrentFailure', 'PowerMeterFailure', 'PowerSwitchFailure',
      'ReaderFailure', 'ResetFailure', 'UnderVoltage', 'OverVoltage',
      'WeakSignal'
    ]::text[])
  )
) tablespace pg_default;

create index if not exists chargers_station_status_connector_idx
  on public.chargers using btree (station_id, status, connector_type);

create trigger chargers_set_updated_at before
update on chargers for each row
execute function set_updated_at ();
