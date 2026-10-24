-- =============================================================================
-- trigger_mock_charger
-- -----------------------------------------------------------------------------
-- Called by pg_cron every 30 seconds (see supabase/sql/cron/mock_charger_tick.sql).
-- If any session is charging, fires an async HTTP POST (pg_net) at the
-- `mock-charger` edge function, which plays the role of the physical chargers
-- and reports OCPP MeterValues. When nobody is charging it returns without
-- calling anything, so idle time costs no edge-function invocations.
--
-- PREREQUISITES (one-time)
--   1. Enable extensions: Dashboard -> Database -> Extensions -> pg_cron, pg_net
--   2. Store the project URL and service role key in Vault:
--        select vault.create_secret('https://<project-ref>.supabase.co', 'project_url');
--        select vault.create_secret('<service_role_key>', 'service_role_key');
--      Use the LEGACY service_role key (a JWT starting with "eyJ"):
--      Project Settings -> API Keys -> Legacy API keys -> service_role.
--      mock-charger checks that the JWT's role is service_role.
--
-- DEBUGGING
--   - Run a tick by hand:     select public.trigger_mock_charger();
--   - Cron history:           select * from cron.job_run_details order by start_time desc limit 20;
--   - HTTP responses (pg_net): select * from net._http_response order by created desc limit 20;
--
-- net.http_post is async: it queues the request and returns immediately, so a
-- slow or failing edge function never blocks the cron job.
-- =============================================================================

create or replace function public.trigger_mock_charger()
returns void
language plpgsql
security definer          -- needs to read vault.decrypted_secrets
set search_path = public
as $$
declare
  v_url text;
  v_key text;
begin
  if not exists (select 1 from charging_sessions where status = 'charging') then
    return;
  end if;

  select decrypted_secret into v_url
  from vault.decrypted_secrets where name = 'project_url';

  select decrypted_secret into v_key
  from vault.decrypted_secrets where name = 'service_role_key';

  if v_url is null or v_key is null then
    raise warning 'trigger_mock_charger: missing vault secret project_url / service_role_key';
    return;
  end if;

  perform net.http_post(
    url     := v_url || '/functions/v1/mock-charger',
    headers := jsonb_build_object(
                 'Content-Type',  'application/json',
                 'Authorization', 'Bearer ' || v_key),
    body    := '{}'::jsonb,
    timeout_milliseconds := 10000
  );
end;
$$;

-- Only cron (running as postgres) should call this.
revoke execute on function public.trigger_mock_charger() from public, anon, authenticated;
