-- =============================================================================
-- host_revenue
-- -----------------------------------------------------------------------------
-- Revenue figures for the signed-in HOST (auth.uid()), for the host
-- dashboard's Revenue tab, header stats and My Chargers cards.
--
-- WHAT COUNTS
--   - Only session_payments with status = 'paid'.
--   - Amounts are the charging bill only (the booking fee is not counted):
--       gross        = session_payments.total_amount   (what the driver paid)
--       platform_fee = session_payments.platform_amount (15%)
--       net          = session_payments.host_amount     (85%, host payout)
--   - A session belongs to the month it STOPPED charging
--     (charging_sessions.ended_at), in Bangkok time.
--
-- PARAMETERS
--   p_month: any date in the month to summarise (null = current month).
--
-- RETURNS jsonb
--   {
--     "month":   "2026-07-01",                       -- selected month
--     "summary": { "gross", "net", "platform_fee", "sessions" },
--     "by_charger": [                                -- selected month
--       { "charger_id", "name", "sessions", "gross", "net" }, ...
--     ],                                             -- every live charger of
--                                                    -- the host (0 if none),
--                                                    -- net desc
--     "monthly": [                                   -- 6 latest months up to
--       { "month": "2026-02-01", "gross", "net" }, ...  -- the CURRENT month,
--     ]                                              -- oldest first, 0-filled
--   }
--
-- WHY SECURITY DEFINER
--   Hosts can't read drivers' session_payments (RLS). This function joins
--   payments -> sessions -> reservations -> chargers on the server, scoped to
--   chargers.host_id = auth.uid(), and returns totals only.
--
-- HOW TO RUN
--   Run in the Supabase SQL Editor. CREATE OR REPLACE, so re-running is safe.
--
-- CALLED BY
--   The app via rpc('host_revenue', { p_month }).
-- =============================================================================

create or replace function public.host_revenue(p_month date default null)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with params as (
    select
      date_trunc('month', coalesce(p_month::timestamp,
                                   now() at time zone 'Asia/Bangkok')) as sel_month,
      date_trunc('month', now() at time zone 'Asia/Bangkok') as cur_month
  ),
  paid as (
    select
      r.charger_id,
      sp.total_amount,
      sp.platform_amount,
      sp.host_amount,
      date_trunc('month', s.ended_at at time zone 'Asia/Bangkok') as month
    from session_payments sp
    join charging_sessions s on s.id = sp.session_id
    join reservations r on r.id = s.reservation_id
    join chargers c on c.id = r.charger_id
    where c.host_id = auth.uid()
      and sp.status = 'paid'
      and s.ended_at is not null
  ),
  sel as (
    select p.*
    from paid p, params
    where p.month = params.sel_month
  ),
  by_charger as (
    select
      c.id as charger_id,
      c.name,
      count(sel.charger_id)::integer as sessions,
      coalesce(sum(sel.total_amount), 0) as gross,
      coalesce(sum(sel.host_amount), 0) as net
    from chargers c
    left join sel on sel.charger_id = c.id
    where c.host_id = auth.uid()
    group by c.id, c.name, c.status
    -- Live chargers always; others only if they earned that month.
    having c.status in ('available', 'unavailable') or count(sel.charger_id) > 0
  ),
  months as (
    select generate_series(cur_month - interval '5 months', cur_month,
                           interval '1 month') as month
    from params
  ),
  monthly as (
    select
      m.month,
      coalesce(sum(p.total_amount), 0) as gross,
      coalesce(sum(p.host_amount), 0) as net
    from months m
    left join paid p on p.month = m.month
    group by m.month
  )
  select jsonb_build_object(
    'month', to_char((select sel_month from params), 'YYYY-MM-DD'),
    'summary', (
      select jsonb_build_object(
        'gross', coalesce(sum(total_amount), 0),
        'net', coalesce(sum(host_amount), 0),
        'platform_fee', coalesce(sum(platform_amount), 0),
        'sessions', count(*)
      )
      from sel
    ),
    'by_charger', (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'charger_id', charger_id,
            'name', name,
            'sessions', sessions,
            'gross', gross,
            'net', net
          )
          order by net desc, name
        ),
        '[]'::jsonb
      )
      from by_charger
    ),
    'monthly', (
      select jsonb_agg(
        jsonb_build_object(
          'month', to_char(month, 'YYYY-MM-DD'),
          'gross', gross,
          'net', net
        )
        order by month
      )
      from monthly
    )
  );
$$;

revoke execute on function public.host_revenue(date) from public, anon;
grant execute on function public.host_revenue(date) to authenticated;
