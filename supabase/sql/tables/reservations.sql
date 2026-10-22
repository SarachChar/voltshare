-- =============================================================================
-- Table: public.reservations
-- -----------------------------------------------------------------------------
-- Schema reference for the `reservations` table. Kept here for reference while
-- developing features; this mirrors the live table definition in Supabase.
--
-- PURPOSE
--   A user's booking of a charger for a time window. Referenced by booking_fee
--   (one fee per reservation).
--
-- RELATIONSHIPS
--   - user_id    -> profiles(id)  ON DELETE CASCADE
--   - charger_id -> chargers(id)  ON DELETE CASCADE
--   - Referenced by: booking_fee.reservation_id (CASCADE)
--
-- INDEXES
--   - reservations_charger_time_idx on (charger_id, start_time)
--   - reservations_user_idx on (user_id)
--
-- TRIGGERS
--   - reservations_set_updated_at: calls set_updated_at() BEFORE UPDATE to keep
--     updated_at current on every row change.
--
-- NOTES
--   - status is one of: confirmed, completed, cancelled (default 'confirmed').
--   - end_time must be after start_time.
--   - duration_minutes must be >= 30, a multiple of 30, and exactly equal to
--     (end_time - start_time) in minutes. The app must send a matching value.
--   - reservations_no_overlap: EXCLUDE constraint that blocks two 'confirmed'
--     reservations on the same charger with overlapping time ranges. Cancelled
--     or completed rows don't block new bookings. Using `=` on a uuid column in
--     a GiST exclusion requires the btree_gist extension.
--   - tstzrange(start_time, end_time) is half-open [start, end), so back-to-back
--     slots (one ends 10:00, next starts 10:00) are allowed.
--   - started_at is nullable; set when the charging session actually begins.
-- =============================================================================

create table public.reservations (
  id uuid not null default gen_random_uuid (),
  user_id uuid not null,
  charger_id uuid not null,
  start_time timestamp with time zone not null,
  end_time timestamp with time zone not null,
  duration_minutes integer not null,
  status character varying(20) not null default 'confirmed'::character varying,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  started_at timestamp with time zone null,
  constraint reservations_pkey primary key (id),
  constraint reservations_user_id_fkey foreign KEY (user_id) references profiles (id) on delete CASCADE,
  constraint reservations_charger_id_fkey foreign KEY (charger_id) references chargers (id) on delete CASCADE,
  constraint reservations_duration_matches check (
    (
      (duration_minutes)::numeric = (
        EXTRACT(
          epoch
          from
            (end_time - start_time)
        ) / (60)::numeric
      )
    )
  ),
  constraint reservations_status_valid check (
    (
      (status)::text = any (
        (
          array[
            'confirmed'::character varying,
            'completed'::character varying,
            'cancelled'::character varying
          ]
        )::text[]
      )
    )
  ),
  constraint reservations_time_order check ((end_time > start_time)),
  constraint reservations_duration_valid check (
    (
      (duration_minutes >= 30)
      and ((duration_minutes % 30) = 0)
    )
  ),
  constraint reservations_no_overlap EXCLUDE using gist (
    charger_id
    with
      =,
      tstzrange (start_time, end_time)
    with
      &&
  )
  where
    (((status)::text = 'confirmed'::text))
) TABLESPACE pg_default;

create index IF not exists reservations_charger_time_idx on public.reservations using btree (charger_id, start_time) TABLESPACE pg_default;

create index IF not exists reservations_user_idx on public.reservations using btree (user_id) TABLESPACE pg_default;

create trigger reservations_set_updated_at BEFORE
update on reservations for EACH row
execute FUNCTION set_updated_at ();
