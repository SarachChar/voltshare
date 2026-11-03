-- =============================================================================
-- Seed: mock stations across Thailand, 1-4 chargers each, + weekly hours
-- -----------------------------------------------------------------------------
-- Run once in the Supabase SQL Editor (after migrations/001_station_layer.sql).
-- Replaces the old seed/mock_chargers.sql.
--
-- WHAT IT CREATES
--   - ~100 rows in public.stations, all owned by host
--     66207295-49bd-4bd8-87d5-03504dcf2c38 (must already exist in profiles).
--       * 40 in Bangkok (20 areas x 2 stations)
--       * the rest in 22 other cities / provinces
--   - 1-4 chargers per station in public.chargers (station_id set), named
--     "Charger 1".."Charger N". Chargers in one station can differ in type /
--     connector / power, so connector filters have something to match.
--   - 7 rows per charger in public.charger_availability (0 = Sunday ..
--     6 = Saturday). All chargers in a station share the station's hours.
--
-- Chargers only get charger fields; location and owner come from the station.
--
-- DETERMINISTIC
--   Station ids:  md5('voltshare-mock-station-<i>')::uuid
--   Charger ids:  md5('voltshare-mock-station-<i>-charger-<j>')::uuid
--   Every "random" value comes from md5, so re-running gives the same data and
--   skips rows that already exist.
--
-- MIX (per charger)
--   35% AC Type 2 7.4 kW | 20% AC Type 2 11 kW | 15% AC Type 2 22 kW |
--   15% DC CCS2 60 kW    |  8% DC CCS2 120 kW  |  4% DC CHAdeMO 50 kW |
--    3% DC CCS2 150 kW
--   Price: AC 6.50-8.50, DC 7.50-9.50 THB/kWh (0.25 steps)
--   Status: ~95% 'available', ~5% 'unavailable'
--   Chargers per station: 1-4 (uniform)
--
-- CLEANUP (mock data only; chargers, hours and child rows cascade):
--   delete from public.stations
--   where id in (select md5('voltshare-mock-station-' || g)::uuid
--                from generate_series(1, 200) g);
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- 1) Stations
-- -----------------------------------------------------------------------------
-- n = number of stations around each anchor point.
create temporary table mock_station on commit drop as
with anchors (ord, area, road, district, province, postcode, lat, lng, n, spread) as (
  values
    -- ---------------- Bangkok: 20 areas x 2 = 40 ----------------
    ( 1, 'Siam',          'Rama I Rd',               'Pathum Wan',  'Bangkok', '10330', 13.7460, 100.5340, 2, 0.008),
    ( 2, 'Asok',          'Sukhumvit Rd',            'Watthana',    'Bangkok', '10110', 13.7370, 100.5600, 2, 0.008),
    ( 3, 'Thong Lo',      'Sukhumvit 55 Rd',         'Watthana',    'Bangkok', '10110', 13.7300, 100.5800, 2, 0.008),
    ( 4, 'Ekkamai',       'Ekkamai Rd',              'Watthana',    'Bangkok', '10110', 13.7220, 100.5860, 2, 0.008),
    ( 5, 'On Nut',        'On Nut Rd',               'Suan Luang',  'Bangkok', '10250', 13.7050, 100.6010, 2, 0.008),
    ( 6, 'Bang Na',       'Bang Na-Trat Rd',         'Bang Na',     'Bangkok', '10260', 13.6680, 100.6050, 2, 0.008),
    ( 7, 'Silom',         'Silom Rd',                'Bang Rak',    'Bangkok', '10500', 13.7280, 100.5320, 2, 0.006),
    ( 8, 'Sathorn',       'Sathorn Rd',              'Sathon',      'Bangkok', '10120', 13.7200, 100.5320, 2, 0.006),
    ( 9, 'Chatuchak',     'Phahonyothin Rd',         'Chatuchak',   'Bangkok', '10900', 13.8020, 100.5530, 2, 0.008),
    (10, 'Ari',           'Phahonyothin Soi 7',      'Phaya Thai',  'Bangkok', '10400', 13.7800, 100.5450, 2, 0.006),
    (11, 'Ratchada',      'Ratchadaphisek Rd',       'Huai Khwang', 'Bangkok', '10310', 13.7690, 100.5740, 2, 0.008),
    (12, 'Lat Phrao',     'Lat Phrao Rd',            'Lat Phrao',   'Bangkok', '10230', 13.8160, 100.5970, 2, 0.008),
    (13, 'Bang Kapi',     'Ramkhamhaeng Rd',         'Bang Kapi',   'Bangkok', '10240', 13.7660, 100.6440, 2, 0.008),
    (14, 'Rama 9',        'Rama IX Rd',              'Huai Khwang', 'Bangkok', '10310', 13.7570, 100.5650, 2, 0.006),
    (15, 'Pinklao',       'Charan Sanitwong Rd',     'Bang Phlat',  'Bangkok', '10700', 13.7770, 100.4790, 2, 0.006),
    (16, 'Bang Khae',     'Phetkasem Rd',            'Bang Khae',   'Bangkok', '10160', 13.7130, 100.4100, 2, 0.008),
    (17, 'Don Mueang',    'Vibhavadi Rangsit Rd',    'Don Mueang',  'Bangkok', '10210', 13.9130, 100.6040, 2, 0.008),
    (18, 'Min Buri',      'Ramkhamhaeng Rd',         'Min Buri',    'Bangkok', '10510', 13.8130, 100.7300, 2, 0.010),
    (19, 'Lat Krabang',   'Lat Krabang Rd',          'Lat Krabang', 'Bangkok', '10520', 13.7270, 100.7590, 2, 0.010),
    (20, 'Bang Sue',      'Pracharat Sai 2 Rd',      'Bang Sue',    'Bangkok', '10800', 13.8060, 100.5300, 2, 0.006),
    -- ---------------- Other cities: 60 ----------------
    (21, 'Nonthaburi',    'Rattanathibet Rd',        'Mueang Nonthaburi',        'Nonthaburi',               '11000', 13.8700, 100.5300, 3, 0.015),
    (22, 'Samut Prakan',  'Theparak Rd',             'Mueang Samut Prakan',      'Samut Prakan',             '10270', 13.6150, 100.6400, 3, 0.015),
    (23, 'Rangsit',       'Phahonyothin Rd',         'Thanyaburi',               'Pathum Thani',             '12130', 13.9890, 100.6170, 3, 0.015),
    (24, 'Nimman',        'Nimmanhaemin Rd',         'Mueang Chiang Mai',        'Chiang Mai',               '50200', 18.7980,  98.9680, 3, 0.012),
    (25, 'Night Bazaar',  'Chang Khlan Rd',          'Mueang Chiang Mai',        'Chiang Mai',               '50100', 18.7880,  98.9980, 3, 0.010),
    (26, 'Phuket Town',   'Phang Nga Rd',            'Mueang Phuket',            'Phuket',                   '83000',  7.8840,  98.3880, 3, 0.010),
    (27, 'Chalong',       'Chao Fa East Rd',         'Mueang Phuket',            'Phuket',                   '83130',  7.8450,  98.3400, 2, 0.008),
    (28, 'Pattaya',       'Pattaya Sai 2 Rd',        'Bang Lamung',              'Chon Buri',                '20150', 12.9300, 100.8920, 3, 0.008),
    (29, 'Chon Buri',     'Sukhumvit Rd',            'Mueang Chon Buri',         'Chon Buri',                '20000', 13.3600, 101.0000, 2, 0.010),
    (30, 'Khon Kaen',     'Mittraphap Rd',           'Mueang Khon Kaen',         'Khon Kaen',                '40000', 16.4320, 102.8350, 4, 0.020),
    (31, 'Korat',         'Mittraphap Rd',           'Mueang Nakhon Ratchasima', 'Nakhon Ratchasima',        '30000', 14.9750, 102.1000, 4, 0.020),
    (32, 'Hat Yai',       'Niphat Uthit 3 Rd',       'Hat Yai',                  'Songkhla',                 '90110',  7.0080, 100.4750, 4, 0.015),
    (33, 'Hua Hin',       'Phetkasem Rd',            'Hua Hin',                  'Prachuap Khiri Khan',      '77110', 12.5700,  99.9450, 3, 0.008),
    (34, 'Udon Thani',    'Prajak Sillapakom Rd',    'Mueang Udon Thani',        'Udon Thani',               '41000', 17.4150, 102.7870, 3, 0.015),
    (35, 'Chiang Rai',    'Phahonyothin Rd',         'Mueang Chiang Rai',        'Chiang Rai',               '57000', 19.9070,  99.8310, 2, 0.012),
    (36, 'Ayutthaya',     'Rojana Rd',               'Phra Nakhon Si Ayutthaya', 'Phra Nakhon Si Ayutthaya', '13000', 14.3530, 100.5680, 2, 0.012),
    (37, 'Rayong',        'Sukhumvit Rd',            'Mueang Rayong',            'Rayong',                   '21000', 12.6900, 101.2700, 3, 0.010),
    (38, 'Surat Thani',   'Talat Mai Rd',            'Mueang Surat Thani',       'Surat Thani',              '84000',  9.1300,  99.3250, 2, 0.008),
    (39, 'Phitsanulok',   'Boromtrailokanat Rd',     'Mueang Phitsanulok',       'Phitsanulok',              '65000', 16.8210, 100.2650, 2, 0.012),
    (40, 'Ubon',          'Chayangkun Rd',           'Mueang Ubon Ratchathani',  'Ubon Ratchathani',         '34000', 15.2440, 104.8480, 2, 0.012),
    (41, 'Nakhon Sawan',  'Sawanwithi Rd',           'Mueang Nakhon Sawan',      'Nakhon Sawan',             '60000', 15.7040, 100.1370, 2, 0.010),
    (42, 'Krabi Town',    'Maharaj Rd',              'Mueang Krabi',             'Krabi',                    '81000',  8.0700,  98.9080, 2, 0.006)
),
expanded as (
  select a.*, k, row_number() over (order by a.ord, k) as i
  from anchors a
  cross join lateral generate_series(1, a.n) as k
),
-- Deterministic pseudo-random numbers in [0, 1) derived from md5.
rnd as (
  select e.*,
    ('x' || substr(md5('st-venue-' || e.i), 1, 7))::bit(28)::int / 268435456.0 as r_venue,
    ('x' || substr(md5('st-no-'    || e.i), 1, 7))::bit(28)::int / 268435456.0 as r_no,
    ('x' || substr(md5('st-moo-'   || e.i), 1, 7))::bit(28)::int / 268435456.0 as r_moo,
    ('x' || substr(md5('st-lat-'   || e.i), 1, 7))::bit(28)::int / 268435456.0 as r_lat,
    ('x' || substr(md5('st-lng-'   || e.i), 1, 7))::bit(28)::int / 268435456.0 as r_lng,
    ('x' || substr(md5('st-count-' || e.i), 1, 7))::bit(28)::int / 268435456.0 as r_count,
    ('x' || substr(md5('st-hours-' || e.i), 1, 7))::bit(28)::int / 268435456.0 as r_hours,
    ('x' || substr(md5('st-age-'   || e.i), 1, 7))::bit(28)::int / 268435456.0 as r_age
  from expanded e
)
select
  md5('voltshare-mock-station-' || r.i)::uuid as id,
  r.i,
  r.area || ' ' || v.venue as name,
  'EV charging at a ' || lower(v.venue) || ' in ' || r.area || ', ' || r.province
    || '. Please book before arriving and park only in the marked EV bays.' as description,
  (10 + floor(r.r_no * 290))::int || '/' || (1 + floor(r.r_moo * 99))::int || ' '
    || r.road || ', ' || r.district || ', ' || r.province || ' ' || r.postcode as address,
  round((r.lat + (r.r_lat * 2 - 1) * r.spread)::numeric, 7) as latitude,
  round((r.lng + (r.r_lng * 2 - 1) * r.spread)::numeric, 7) as longitude,
  1 + floor(r.r_count * 4)::int as charger_count,
  case
    when r.r_hours < 0.30 then 'daily_06_23'
    when r.r_hours < 0.55 then 'daily_08_20'
    when r.r_hours < 0.75 then 'evenings_weekends'
    when r.r_hours < 0.90 then 'mon_sat'
    else 'near_24h'
  end as hours_pattern,
  now() - (r.r_age::float8 * interval '180 days') as created_at
from rnd r
cross join lateral (
  select (array['EV Hub', 'Mall Parking', 'Condo Parking', 'Café',
                'Hotel Parking', 'Office Lot', 'Co-working Space', 'Gas Station']
         )[1 + floor(r.r_venue * 8)::int] as venue
) v;

insert into public.stations (
  id, host_id, name, description, address, latitude, longitude, created_at
)
select
  s.id,
  '66207295-49bd-4bd8-87d5-03504dcf2c38'::uuid,
  s.name, s.description, s.address, s.latitude, s.longitude, s.created_at
from mock_station s
order by s.i
on conflict (id) do nothing;

-- -----------------------------------------------------------------------------
-- 2) Chargers (1-4 per station)
-- -----------------------------------------------------------------------------
with slots as (
  select s.*, j,
    ('x' || substr(md5('ch-spec-'  || s.i || '-' || j), 1, 7))::bit(28)::int / 268435456.0 as r_spec,
    ('x' || substr(md5('ch-price-' || s.i || '-' || j), 1, 7))::bit(28)::int / 268435456.0 as r_price,
    ('x' || substr(md5('ch-stat-'  || s.i || '-' || j), 1, 7))::bit(28)::int / 268435456.0 as r_status
  from mock_station s
  cross join lateral generate_series(1, s.charger_count) as j
)
insert into public.chargers (
  id, station_id, name, charger_type, connector_type, power_kw, price_per_kwh,
  status, created_at
)
select
  md5('voltshare-mock-station-' || sl.i || '-charger-' || sl.j)::uuid,
  sl.id,
  'Charger ' || sl.j,
  t.charger_type,
  t.connector_type,
  t.power_kw,
  -- AC 6.50-8.50, DC 7.50-9.50, rounded to 0.25 THB
  round(((case when t.charger_type = 'AC' then 6.50 else 7.50 end) + sl.r_price * 2.0) * 4) / 4,
  case when sl.r_status < 0.05 then 'unavailable' else 'available' end,
  sl.created_at
from slots sl
cross join lateral (
  select spec.charger_type, spec.connector_type, spec.power_kw
  from (values
    (1, 0.35, 'AC', 'Type 2',   7.40),
    (2, 0.55, 'AC', 'Type 2',  11.00),
    (3, 0.70, 'AC', 'Type 2',  22.00),
    (4, 0.85, 'DC', 'CCS2',    60.00),
    (5, 0.93, 'DC', 'CCS2',   120.00),
    (6, 0.97, 'DC', 'CHAdeMO', 50.00),
    (7, 1.01, 'DC', 'CCS2',   150.00)
  ) as spec(o, threshold, charger_type, connector_type, power_kw)
  where sl.r_spec < spec.threshold
  order by spec.o
  limit 1
) t
order by sl.i, sl.j
on conflict (id) do nothing;

-- -----------------------------------------------------------------------------
-- 3) Weekly availability (7 rows per charger, station's pattern; skipped if the
--    charger already has rows). Closed days keep 07:00-22:00 with
--    is_available = false, same shape the Add Charger screen saves.
-- -----------------------------------------------------------------------------
insert into public.charger_availability (charger_id, day_of_week, start_time, end_time, is_available)
select
  c.id,
  d,
  (case s.hours_pattern
     when 'daily_06_23'       then '06:00'
     when 'daily_08_20'       then '08:00'
     when 'evenings_weekends' then case when d between 1 and 5 then '18:00' else '08:00' end
     when 'mon_sat'           then case when d = 0 then '07:00' else '09:00' end
     else                          '00:00'
   end)::time,
  (case s.hours_pattern
     when 'daily_06_23'       then '23:00'
     when 'daily_08_20'       then '20:00'
     when 'evenings_weekends' then case when d between 1 and 5 then '23:30' else '22:00' end
     when 'mon_sat'           then case when d = 0 then '22:00' else '21:00' end
     else                          '23:30'
   end)::time,
  not (s.hours_pattern = 'mon_sat' and d = 0)
from public.chargers c
join mock_station s on s.id = c.station_id
cross join generate_series(0, 6) as d
where not exists (
  select 1 from public.charger_availability ca where ca.charger_id = c.id
)
order by c.id, d;

commit;

-- -----------------------------------------------------------------------------
-- Quick checks (optional)
-- -----------------------------------------------------------------------------
-- Stations / chargers / availability rows:
--   select (select count(*) from stations) as stations,
--          (select count(*) from chargers) as chargers,
--          (select count(*) from charger_availability) as availability;  -- = chargers x 7
--
-- Chargers per station (expect 1-4):
--   select n, count(*) from (select station_id, count(*) n from chargers group by 1) x
--   group by 1 order by 1;
--
-- Stations with mixed connector types (useful for search tests):
--   select s.name, array_agg(distinct c.connector_type) from stations s
--   join chargers c on c.station_id = s.id group by s.id, s.name
--   having count(distinct c.connector_type) > 1 limit 10;
