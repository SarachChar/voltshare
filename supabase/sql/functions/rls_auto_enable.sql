-- =============================================================================
-- rls_auto_enable + event trigger ensure_rls
-- -----------------------------------------------------------------------------
-- Safety net: every table created in the `public` schema (CREATE TABLE,
-- CREATE TABLE AS, SELECT INTO) gets row level security enabled automatically,
-- so a table can't be exposed through the API by forgetting
-- `enable row level security`. RLS on with no policies = no access for
-- anon/authenticated until policies are added.
--
-- Copied from the original project (it was created by Supabase's "automatic
-- RLS" project option, not by a repo file). Table files should still enable
-- RLS explicitly; this only catches mistakes.
--
-- HOW TO RUN
--   Run once in the SQL Editor. Safe to re-run (CREATE OR REPLACE + drop/create
--   of the event trigger).
--
-- DEBUGGING
--   Logs go to the Postgres logs ("rls_auto_enable: enabled RLS on ...").
--   Check it's installed:
--     select evtname, evtevent, evtfoid::regproc, evtenabled from pg_event_trigger
--     where evtname = 'ensure_rls';
-- =============================================================================

CREATE OR REPLACE FUNCTION public.rls_auto_enable()
 RETURNS event_trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$function$;

-- No grant/revoke needed: a function returning event_trigger can only be
-- fired by the event trigger, never called directly (e.g. via the API).
drop event trigger if exists ensure_rls;

create event trigger ensure_rls
  on ddl_command_end
  execute function public.rls_auto_enable();
