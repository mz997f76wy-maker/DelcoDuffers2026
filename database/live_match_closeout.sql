-- Automatically synchronize final results with the latest live status.
-- Runs with the scoring user's existing row-level permissions.
CREATE OR REPLACE FUNCTION public.duffers_sync_live_result()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  tid text;
  rnd integer;
  mno integer;
  latest public.tournament_live_status%ROWTYPE;
  winning_team text;
BEGIN
  IF TG_OP = 'DELETE' THEN
    tid := OLD.tournament_id; rnd := OLD.round_no; mno := OLD.match_no;
  ELSE
    tid := NEW.tournament_id; rnd := NEW.round_no; mno := NEW.match_no;
  END IF;
  IF tid <> 'delco-duffers-2026' THEN RETURN NULL; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(tid || ':' || rnd || ':' || mno, 0));
  SELECT * INTO latest FROM public.tournament_live_status
  WHERE tournament_id = tid AND round_no = rnd AND match_no = mno
  ORDER BY holes_completed DESC LIMIT 1;
  IF FOUND AND latest.holes_completed BETWEEN 1 AND 18 AND latest.margin BETWEEN 0 AND latest.holes_completed THEN
    IF latest.leader IN ('Hackers','Shankers') AND latest.margin > 18 - latest.holes_completed THEN
      winning_team := latest.leader;
    ELSIF latest.holes_completed = 18 AND latest.leader = 'All square' AND latest.margin = 0 THEN
      winning_team := 'Halved';
    END IF;
  END IF;
  IF winning_team IS NOT NULL THEN
    INSERT INTO public.tournament_results(tournament_id,round_no,match_no,winner,updated_at)
    VALUES(tid,rnd,mno,winning_team,pg_catalog.now())
    ON CONFLICT(tournament_id,round_no,match_no)
    DO UPDATE SET winner = EXCLUDED.winner, updated_at = EXCLUDED.updated_at;
  ELSE
    DELETE FROM public.tournament_results WHERE tournament_id = tid AND round_no = rnd AND match_no = mno;
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.duffers_sync_live_result() FROM PUBLIC;
DROP TRIGGER IF EXISTS duffers_live_result_closeout ON public.tournament_live_status;
CREATE TRIGGER duffers_live_result_closeout
AFTER INSERT OR UPDATE OR DELETE ON public.tournament_live_status
FOR EACH ROW EXECUTE FUNCTION public.duffers_sync_live_result();
