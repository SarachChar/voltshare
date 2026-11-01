-- =============================================================================
-- Seed: 250 mock chargers across Thailand + weekly availability
-- -----------------------------------------------------------------------------
-- Run once in the Supabase SQL Editor.
--
-- WHAT IT CREATES
--   - 250 rows in public.chargers, all owned by host
--     b2a03fe2-086d-4ec6-adb4-e76a7927326e (must already exist in profiles).
--       * 100 in Bangkok (20 districts x 5 chargers)
--       * 150 in 19 other cities / provinces
--   - 7 rows per charger in public.charger_availability (one per day of week,
--     0 = Sunday .. 6 = Saturday), same shape the Add Charger screen saves:
--     closed days keep 07:00-22:00 with is_available = false.
--
-- DETERMINISTIC
--   Charger ids are md5('voltshare-mock-charger-<n>')::uuid for n = 1..250 and
--   every "random" value is derived from an md5 hash, so re-running the script
--   produces the same data and skips rows that already exist.
--
-- MIX
--   Specs (by share):  35% AC Type 2 7.4 kW | 20% AC Type 2 11 kW |
--                      15% AC Type 2 22 kW  | 15% DC CCS2 60 kW   |
--                       8% DC CCS2 120 kW   |  4% DC CHAdeMO 50 kW |
--                       3% DC CCS2 150 kW
--   Price:  AC 6.50-8.50 THB/kWh, DC 7.50-9.50 THB/kWh (0.25 steps)
--   Status: ~95% 'available', ~5% 'unavailable'
--   Hours:  30% daily 06:00-23:00 | 25% daily 08:00-20:00 |
--           20% Mon-Fri 18:00-23:30, Sat-Sun 08:00-22:00 |
--           15% Mon-Sat 09:00-21:00, Sunday closed |
--           10% daily 00:00-23:30
--
-- CLEANUP (removes only the mock chargers; availability cascades):
--   delete from public.chargers
--   where id in (select md5('voltshare-mock-charger-' || g)::uuid
--                from generate_series(1, 250) g);
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- 1) Chargers
-- -----------------------------------------------------------------------------
with anchors (ord, area, road, district, province, postcode, lat, lng, n, spread) as (
  values
    -- ---------------- Bangkok: 20 areas x 5 = 100 ----------------
    ( 1, 'Siam',          'Rama I Rd',               'Pathum Wan',  'Bangkok', '10330', 13.7460, 100.5340, 5, 0.008),
    ( 2, 'Asok',          'Sukhumvit Rd',            'Watthana',    'Bangkok', '10110', 13.7370, 100.5600, 5, 0.008),
    ( 3, 'Thong Lo',      'Sukhumvit 55 Rd',         'Watthana',    'Bangkok', '10110', 13.7300, 100.5800, 5, 0.008),
    ( 4, 'Ekkamai',       'Ekkamai Rd',              'Watthana',    'Bangkok', '10110', 13.7220, 100.5860, 5, 0.008),
    ( 5, 'On Nut',        'On Nut Rd',               'Suan Luang',  'Bangkok', '10250', 13.7050, 100.6010, 5, 0.008),
    ( 6, 'Bang Na',       'Bang Na-Trat Rd',         'Bang Na',     'Bangkok', '10260', 13.6680, 100.6050, 5, 0.008),
    ( 7, 'Silom',         'Silom Rd',                'Bang Rak',    'Bangkok', '10500', 13.7280, 100.5320, 5, 0.006),
    ( 8, 'Sathorn',       'Sathorn Rd',              'Sathon',      'Bangkok', '10120', 13.7200, 100.5320, 5, 0.006),
    ( 9, 'Chatuchak',     'Phahonyothin Rd',         'Chatuchak',   'Bangkok', '10900', 13.8020, 100.5530, 5, 0.008),
    (10, 'Ari',           'Phahonyothin Soi 7',      'Phaya Thai',  'Bangkok', '10400', 13.7800, 100.5450, 5, 0.006),
    (11, 'Ratchada',      'Ratchadaphisek Rd',       'Huai Khwang', 'Bangkok', '10310', 13.7690, 100.5740, 5, 0.008),
    (12, 'Lat Phrao',     'Lat Phrao Rd',            'Lat Phrao',   'Bangkok', '10230', 13.8160, 100.5970, 5, 0.008),
    (13, 'Bang Kapi',     'Ramkhamhaeng Rd',         'Bang Kapi',   'Bangkok', '10240', 13.7660, 100.6440, 5, 0.008),
    (14, 'Rama 9',        'Rama IX Rd',              'Huai Khwang', 'Bangkok', '10310', 13.7570, 100.5650, 5, 0.006),
    (15, 'Pinklao',       'Charan Sanitwong Rd',     'Bang Phlat',  'Bangkok', '10700', 13.7770, 100.4790, 5, 0.006),
    (16, 'Bang Khae',     'Phetkasem Rd',            'Bang Khae',   'Bangkok', '10160', 13.7130, 100.4100, 5, 0.008),
    (17, 'Don Mueang',    'Vibhavadi Rangsit Rd',    'Don Mueang',  'Bangkok', '10210', 13.9130, 100.6040, 5, 0.008),
    (18, 'Min Buri',      'Ramkhamhaeng Rd',         'Min Buri',    'Bangkok', '10510', 13.8130, 100.7300, 5, 0.010),
    (19, 'Lat Krabang',   'Lat Krabang Rd',          'Lat Krabang', 'Bangkok', '10520', 13.7270, 100.7590, 5, 0.010),
    (20, 'Bang Sue',      'Pracharat Sai 2 Rd',      'Bang Sue',    'Bangkok', '10800', 13.8060, 100.5300, 5, 0.006),
    -- ---------------- Other cities: 150 ----------------
    (21, 'Nonthaburi',    'Rattanathibet Rd',        'Mueang Nonthaburi',        'Nonthaburi',               '11000', 13.8700, 100.5300,  7, 0.015),
    (22, 'Samut Prakan',  'Theparak Rd',             'Mueang Samut Prakan',      'Samut Prakan',             '10270', 13.6150, 100.6400,  8, 0.015),
    (23, 'Rangsit',       'Phahonyothin Rd',         'Thanyaburi',               'Pathum Thani',             '12130', 13.9890, 100.6170,  7, 0.015),
    (24, 'Nimman',        'Nimmanhaemin Rd',         'Mueang Chiang Mai',        'Chiang Mai',               '50200', 18.7980,  98.9680,  8, 0.012),
    (25, 'Night Bazaar',  'Chang Khlan Rd',          'Mueang Chiang Mai',        'Chiang Mai',               '50100', 18.7880,  98.9980,  7, 0.010),
    (26, 'Phuket Town',   'Phang Nga Rd',            'Mueang Phuket',            'Phuket',                   '83000',  7.8840,  98.3880,  7, 0.010),
    (27, 'Chalong',       'Chao Fa East Rd',         'Mueang Phuket',            'Phuket',                   '83130',  7.8450,  98.3400,  5, 0.008),
    (28, 'Pattaya',       'Pattaya Sai 2 Rd',        'Bang Lamung',              'Chon Buri',                '20150', 12.9300, 100.8920,  8, 0.008),
    (29, 'Chon Buri',     'Sukhumvit Rd',            'Mueang Chon Buri',         'Chon Buri',                '20000', 13.3600, 101.0000,  6, 0.010),
    (30, 'Khon Kaen',     'Mittraphap Rd',           'Mueang Khon Kaen',         'Khon Kaen',                '40000', 16.4320, 102.8350, 10, 0.020),
    (31, 'Korat',         'Mittraphap Rd',           'Mueang Nakhon Ratchasima', 'Nakhon Ratchasima',        '30000', 14.9750, 102.1000, 10, 0.020),
    (32, 'Hat Yai',       'Niphat Uthit 3 Rd',       'Hat Yai',                  'Songkhla',                 '90110',  7.0080, 100.4750, 10, 0.015),
    (33, 'Hua Hin',       'Phetkasem Rd',            'Hua Hin',                  'Prachuap Khiri Khan',      '77110', 12.5700,  99.9450,  8, 0.008),
    (34, 'Udon Thani',    'Prajak Sillapakom Rd',    'Mueang Udon Thani',        'Udon Thani',               '41000', 17.4150, 102.7870,  8, 0.015),
    (35, 'Chiang Rai',    'Phahonyothin Rd',         'Mueang Chiang Rai',        'Chiang Rai',               '57000', 19.9070,  99.8310,  6, 0.012),
    (36, 'Ayutthaya',     'Rojana Rd',               'Phra Nakhon Si Ayutthaya', 'Phra Nakhon Si Ayutthaya', '13000', 14.3530, 100.5680,  5, 0.012),
    (37, 'Rayong',        'Sukhumvit Rd',            'Mueang Rayong',            'Rayong',                   '21000', 12.6900, 101.2700,  7, 0.010),
    (38, 'Surat Thani',   'Talat Mai Rd',            'Mueang Surat Thani',       'Surat Thani',              '84000',  9.1300,  99.3250,  5, 0.008),
    (39, 'Phitsanulok',   'Boromtrailokanat Rd',     'Mueang Phitsanulok',       'Phitsanulok',              '65000', 16.8210, 100.2650,  5, 0.012),
    (40, 'Ubon',          'Chayangkun Rd',           'Mueang Ubon Ratchathani',  'Ubon Ratchathani',         '34000', 15.2440, 104.8480,  5, 0.012),
    (41, 'Nakhon Sawan',  'Sawanwithi Rd',           'Mueang Nakhon Sawan',      'Nakhon Sawan',             '60000', 15.7040, 100.1370,  4, 0.010),
    (42, 'Krabi Town',    'Maharaj Rd',              'Mueang Krabi',             'Krabi',                    '81000',  8.0700,  98.9080,  4, 0.006)
),
expanded as (
  select a.*, k, row_number() over (order by a.ord, k) as i
  from anchors a
  cross join lateral generate_series(1, a.n) as k
),
-- Deterministic pseudo-random numbers in [0, 1) derived from md5.
rnd as (
  select e.*,
    ('x' || substr(md5('spec-'  || e.i), 1, 7))::bit(28)::int / 268435456.0 as r_spec,
    ('x' || substr(md5('venue-' || e.i), 1, 7))::bit(28)::int / 268435456.0 as r_venue,
    ('x' || substr(md5('no-'    || e.i), 1, 7))::bit(28)::int / 268435456.0 as r_no,
    ('x' || substr(md5('moo-'   || e.i), 1, 7))::bit(28)::int / 268435456.0 as r_moo,
    ('x' || substr(md5('lat-'   || e.i), 1, 7))::bit(28)::int / 268435456.0 as r_lat,
    ('x' || substr(md5('lng-'   || e.i), 1, 7))::bit(28)::int / 268435456.0 as r_lng,
    ('x' || substr(md5('price-' || e.i), 1, 7))::bit(28)::int / 268435456.0 as r_price,
    ('x' || substr(md5('stat-'  || e.i), 1, 7))::bit(28)::int / 268435456.0 as r_status,
    ('x' || substr(md5('age-'   || e.i), 1, 7))::bit(28)::int / 268435456.0 as r_age
  from expanded e
),
built as (
  select
    md5('voltshare-mock-charger-' || r.i)::uuid as id,
    r.*,
    s.charger_type,
    s.connector_type,
    s.power_kw,
    (array['Home Garage', 'Condo Parking', 'Café', 'Shophouse',
           'Office Lot', 'Townhouse', 'Hotel Parking', 'Co-working Space']
    )[1 + floor(r.r_venue * 8)::int] as venue
  from rnd r
  cross join lateral (
    select t.charger_type, t.connector_type, t.power_kw
    from (values
      (1, 0.35, 'AC', 'Type 2',   7.40),
      (2, 0.55, 'AC', 'Type 2',  11.00),
      (3, 0.70, 'AC', 'Type 2',  22.00),
      (4, 0.85, 'DC', 'CCS2',    60.00),
      (5, 0.93, 'DC', 'CCS2',   120.00),
      (6, 0.97, 'DC', 'CHAdeMO', 50.00),
      (7, 1.01, 'DC', 'CCS2',   150.00)
    ) as t(o, threshold, charger_type, connector_type, power_kw)
    where r.r_spec < t.threshold
    order by t.o
    limit 1
  ) s
)
insert into public.chargers (
  id, host_id, name, description, address, latitude, longitude,
  charger_type, connector_type, power_kw, price_per_kwh, status, created_at
)
select
  b.id,
  'b2a03fe2-086d-4ec6-adb4-e76a7927326e'::uuid,
  b.area || ' ' || b.venue || ' #' || b.k,
  (b.power_kw::float8)::text || ' kW ' || b.charger_type || ' (' || b.connector_type || ') charger at a '
    || lower(b.venue) || ' in ' || b.area || ', ' || b.province
    || '. Please book before arriving and park only in the marked EV bay.',
  (10 + floor(b.r_no * 290))::int || '/' || (1 + floor(b.r_moo * 99))::int || ' '
    || b.road || ', ' || b.district || ', ' || b.province || ' ' || b.postcode,
  round((b.lat + (b.r_lat * 2 - 1) * b.spread)::numeric, 7),
  round((b.lng + (b.r_lng * 2 - 1) * b.spread)::numeric, 7),
  b.charger_type,
  b.connector_type,
  b.power_kw,
  -- AC 6.50-8.50, DC 7.50-9.50, rounded to 0.25 THB
  round(((case when b.charger_type = 'AC' then 6.50 else 7.50 end) + b.r_price * 2.0) * 4) / 4,
  case when b.r_status < 0.05 then 'unavailable' else 'available' end,
  now() - (b.r_age::float8 * interval '180 days')
from built b
order by b.i
on conflict (id) do nothing;

-- -----------------------------------------------------------------------------
-- 2) Weekly availability (7 rows per mock charger, skipped if already present)
-- -----------------------------------------------------------------------------
with mock as (
  select c.id,
    case
      when p < 0.30 then 'daily_06_23'
      when p < 0.55 then 'daily_08_20'
      when p < 0.75 then 'evenings_weekends'
      when p < 0.90 then 'mon_sat'
      else 'near_24h'
    end as pattern
  from public.chargers c
  cross join lateral (
    select ('x' || substr(md5('avail-' || c.id::text), 1, 7))::bit(28)::int / 268435456.0 as p
  ) pr
  where c.id in (
    select md5('voltshare-mock-charger-' || g)::uuid from generate_series(1, 250) g
  )
  and not exists (
    select 1 from public.charger_availability ca where ca.charger_id = c.id
  )
)
insert into public.charger_availability (charger_id, day_of_week, start_time, end_time, is_available)
select
  m.id,
  d,
  (case m.pattern
     when 'daily_06_23'       then '06:00'
     when 'daily_08_20'       then '08:00'
     when 'evenings_weekends' then case when d between 1 and 5 then '18:00' else '08:00' end
     when 'mon_sat'           then case when d = 0 then '07:00' else '09:00' end
     else                          '00:00'
   end)::time,
  (case m.pattern
     when 'daily_06_23'       then '23:00'
     when 'daily_08_20'       then '20:00'
     when 'evenings_weekends' then case when d between 1 and 5 then '23:30' else '22:00' end
     when 'mon_sat'           then case when d = 0 then '22:00' else '21:00' end
     else                          '23:30'
   end)::time,
  not (m.pattern = 'mon_sat' and d = 0)
from mock m
cross join generate_series(0, 6) as d
order by m.id, d;

commit;

-- -----------------------------------------------------------------------------
-- Quick checks (optional)
-- -----------------------------------------------------------------------------
-- Chargers per province (expect Bangkok = 100, total = 250):
--   select split_part(address, ', ', 3) as province_and_zip, count(*)
--   from public.chargers
--   where id in (select md5('voltshare-mock-charger-' || g)::uuid from generate_series(1, 250) g)
--   group by 1 order by 2 desc;
--
-- Availability rows (expect 1750 = 250 x 7):
--   select count(*) from public.charger_availability
--   where charger_id in (select md5('voltshare-mock-charger-' || g)::uuid from generate_series(1, 250) g);
