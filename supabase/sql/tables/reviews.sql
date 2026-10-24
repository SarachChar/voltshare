-- =============================================================================
-- Table: public.reviews
-- -----------------------------------------------------------------------------
-- PURPOSE
--   A driver's review of a finished charging booking. One review per
--   reservation (1-1, enforced by a unique constraint on reservation_id).
--   Reviews are write-once: no update/delete policies, so after submitting the
--   app shows the review read-only.
--
-- RELATIONSHIPS
--   - reservation_id -> reservations(id)  ON DELETE CASCADE  (unique)
--
-- TRIGGERS
--   - reviews_set_updated_at: set_updated_at() BEFORE UPDATE.
--
-- NOTES
--   - rating: 1-5  (1 Terrible, 2 Poor, 3 Okay, 4 Good, 5 Excellent).
--   - comment: optional, max 500 characters.
--   - RLS (bottom of this file):
--       SELECT: any signed-in user (reviews are public, e.g. shown on the
--               charger details screen).
--       INSERT: the owner, only when the reservation is 'completed'.
--       No UPDATE / DELETE policies: reviews are write-once.
--
-- HOW TO RUN
--   Run once in the Supabase SQL Editor (needs set_updated_at() to exist).
-- =============================================================================

create table public.reviews (
  id uuid not null default gen_random_uuid (),
  reservation_id uuid not null,
  rating integer not null,
  comment text null,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  constraint reviews_pkey primary key (id),
  constraint reviews_reservation_id_key unique (reservation_id),
  constraint reviews_reservation_id_fkey foreign key (reservation_id)
    references reservations (id) on delete cascade,
  constraint reviews_rating_valid check (rating >= 1 and rating <= 5),
  constraint reviews_comment_length check (
    comment is null or char_length(comment) <= 500
  )
) tablespace pg_default;

create trigger reviews_set_updated_at before
update on reviews for each row
execute function set_updated_at ();

-- -----------------------------------------------------------------------------
-- RLS
-- -----------------------------------------------------------------------------
alter table public.reviews enable row level security;

create policy "Signed-in users read all reviews"
  on public.reviews for select
  to authenticated
  using (true);

create policy "Drivers review own completed reservations"
  on public.reviews for insert
  to authenticated
  with check (
    exists (
      select 1 from public.reservations r
      where r.id = reviews.reservation_id
        and r.user_id = auth.uid()
        and r.status = 'completed'
    )
  );
