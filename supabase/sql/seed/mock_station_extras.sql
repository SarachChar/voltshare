-- =============================================================================
-- Seed: mock businesses + promotions for ~30% of the mock stations
-- -----------------------------------------------------------------------------
-- Run once in the Supabase SQL Editor after seed/mock_stations.sql. Gives the
-- Station Detail screen something to show in its Business tab. No photos (those
-- need real files in storage).
--
-- WHAT IT CREATES (deterministic, md5-based like the other seeds)
--   - Stations whose md5('extras-<i>') falls in the lowest 30% get:
--       * 1-2 rows in station_businesses
--       * 1 ACTIVE row in station_promotions, valid from now for 30-90 days
--   - Re-running skips stations that already have businesses / promotions.
--
-- CLEANUP
--   delete from public.station_businesses
--   where station_id in (select md5('voltshare-mock-station-' || g)::uuid
--                        from generate_series(1, 200) g);
--   delete from public.station_promotions
--   where station_id in (select md5('voltshare-mock-station-' || g)::uuid
--                        from generate_series(1, 200) g);
-- =============================================================================

begin;

create temporary table mock_extra on commit drop as
select
  s.id,
  g as i,
  ('x' || substr(md5('extras-'   || g), 1, 7))::bit(28)::int / 268435456.0 as r_pick,
  ('x' || substr(md5('biz-n-'    || g), 1, 7))::bit(28)::int / 268435456.0 as r_count,
  ('x' || substr(md5('biz-a-'    || g), 1, 7))::bit(28)::int / 268435456.0 as r_biz_a,
  ('x' || substr(md5('biz-b-'    || g), 1, 7))::bit(28)::int / 268435456.0 as r_biz_b,
  ('x' || substr(md5('promo-'    || g), 1, 7))::bit(28)::int / 268435456.0 as r_promo,
  ('x' || substr(md5('promo-d-'  || g), 1, 7))::bit(28)::int / 268435456.0 as r_days
from generate_series(1, 200) g
join public.stations s on s.id = md5('voltshare-mock-station-' || g)::uuid;

-- Business catalogue: (type, name, description).
create temporary table mock_biz_catalogue on commit drop as
select * from (values
  (1, 'CAFE',        'Bean & Bolt Coffee',   'Espresso, cold brew and pastries. Show your booking for 10% off.'),
  (2, 'RESTAURANT',  'Charge & Chill Kitchen','Thai and international dishes, ready in 15 minutes.'),
  (3, 'CONVENIENCE', 'QuickStop Mart',        'Snacks, drinks and essentials, open late.'),
  (4, 'CO_WORKING',  'PlugIn Desk',           'Day passes with fast Wi-Fi and meeting rooms.'),
  (5, 'GYM',         'Volt Fitness',          'Drop-in gym session while you charge.'),
  (6, 'SALON',       'Quick Cut Studio',      'Express haircut in about 30 minutes.'),
  (7, 'RETAIL',      'Daily Goods',           'Household items and gifts.'),
  (8, 'OTHER',       'Car Care Corner',       'Interior vacuum and quick wash.')
) as t(o, business_type, business_name, description);

-- Businesses: first one always, second one for half of the picked stations.
insert into public.station_businesses (station_id, business_type, business_name, description)
select e.id, c.business_type, c.business_name, c.description
from mock_extra e
join mock_biz_catalogue c on c.o = 1 + floor(e.r_biz_a * 8)::int
where e.r_pick < 0.30
  and not exists (select 1 from public.station_businesses b where b.station_id = e.id)
union all
select e.id, c.business_type, c.business_name, c.description
from mock_extra e
join mock_biz_catalogue c on c.o = 1 + floor(e.r_biz_b * 8)::int
where e.r_pick < 0.30
  and e.r_count < 0.5
  and floor(e.r_biz_b * 8)::int <> floor(e.r_biz_a * 8)::int
  and not exists (select 1 from public.station_businesses b where b.station_id = e.id);

-- One ACTIVE promotion per picked station.
insert into public.station_promotions (
  station_id, title, description, valid_from, valid_until, status, terms_and_conditions
)
select
  e.id,
  p.title,
  p.description,
  now(),
  now() + ((30 + floor(e.r_days * 61))::int * interval '1 day'),
  'ACTIVE',
  'One use per booking. Cannot be combined with other offers.'
from mock_extra e
cross join lateral (
  select * from (values
    (1, 'Free coffee with 1-hour booking', 'Book at least 1 hour and get a free drink at the partner café.'),
    (2, '10% off DC fast charging',         'Valid on weekday mornings before 11:00.'),
    (3, 'Weekend parking on us',            'Free parking for the length of your booking on Sat-Sun.'),
    (4, 'Double points this month',         'Earn 2x points on every completed session.')
  ) as t(o, title, description)
  where t.o = 1 + floor(e.r_promo * 4)::int
) p
where e.r_pick < 0.30
  and not exists (select 1 from public.station_promotions sp where sp.station_id = e.id);

commit;

-- Quick check:
--   select (select count(distinct station_id) from station_businesses) as stations_with_biz,
--          (select count(*) from station_businesses) as businesses,
--          (select count(*) from station_promotions) as promotions;
