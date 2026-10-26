-- =============================================================================
-- Table: public.chargers
-- -----------------------------------------------------------------------------
-- Schema reference for the `chargers` table. Kept here for reference while
-- developing features; this mirrors the live table definition in Supabase.
--
-- PURPOSE
--   Core table describing each EV charger listing: owner (host), location,
--   hardware specs, pricing, and listing status. Many other tables reference
--   this one (business_images, charger_availability, charger_businesses,
--   charger_images, charger_promotions).
--
-- RELATIONSHIPS
--   - host_id -> profiles(id)  ON DELETE CASCADE
--
-- NOTES
--   - latitude/longitude are numeric(10,7); used by the search functions
--     (see supabase/sql/functions/) via earthdistance.
--   - status is one of: review, setup, available, unavailable, rejected
--     (default 'available'), enforced by a check constraint.
--   - price_per_kwh and power_kw are numeric(10,2).
--   - mock_error_code: TEST SWITCH for the mock charger (ocpp-status edge
--     function). Null = connector Available; set to an OCPP errorCode
--     (e.g. 'GroundFailure') = Unavailable, so "I've Plugged In" cancels the
--     booking and refunds its fee (refund_booking_fee).
--     Not read by the app. Added with the ALTER at the bottom of this file.
-- =============================================================================

create table public.chargers (
  id uuid not null default gen_random_uuid (),
  host_id uuid not null,
  name character varying not null,
  description text null,
  address text null,
  latitude numeric(10, 7) null,
  longitude numeric(10, 7) null,
  charger_type character varying null,
  connector_type character varying null,
  power_kw numeric(10, 2) null,
  price_per_kwh numeric(10, 2) null,
  status character varying not null default 'available'::character varying,
  created_at timestamp with time zone null default now(),
  updated_at timestamp with time zone null default now(),
  constraint chargers_pkey primary key (id),
  constraint chargers_host_id_fkey foreign KEY (host_id) references profiles (id) on delete CASCADE,
  constraint chargers_status_check check (
    (
      (status)::text = any (
        array[
          ('review'::character varying)::text,
          ('setup'::character varying)::text,
          ('available'::character varying)::text,
          ('unavailable'::character varying)::text,
          ('rejected'::character varying)::text
        ]
      )
    )
  )
) TABLESPACE pg_default;

-- -----------------------------------------------------------------------------
-- Mock charger status switch (run once in the SQL Editor).
--   update chargers set mock_error_code = 'GroundFailure' where id = '<uuid>';
--   update chargers set mock_error_code = null            where id = '<uuid>';
-- -----------------------------------------------------------------------------
alter table public.chargers
  add column if not exists mock_error_code character varying(40) null;

alter table public.chargers
  add constraint chargers_mock_error_code_valid check (
    mock_error_code is null
    or (mock_error_code)::text = any (array[
      'ConnectorLockFailure', 'EVCommunicationError', 'GroundFailure',
      'HighTemperature', 'InternalError', 'LocalListConflict', 'OtherError',
      'OverCurrentFailure', 'PowerMeterFailure', 'PowerSwitchFailure',
      'ReaderFailure', 'ResetFailure', 'UnderVoltage', 'OverVoltage',
      'WeakSignal'
    ]::text[])
  );
