-- Owner-only full scoring reset, including live match history.
CREATE OR REPLACE FUNCTION public.reset_duffers_scores()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL OR public.duffers_role() IS DISTINCT FROM 'owner' THEN
    RAISE EXCEPTION 'Owner access required';
  END IF;
  DELETE FROM public.tournament_scores WHERE tournament_id='delco-duffers-2026';
  -- Delete statuses first: their closeout trigger may synchronize a result.
  DELETE FROM public.tournament_live_status WHERE tournament_id='delco-duffers-2026';
  DELETE FROM public.tournament_results WHERE tournament_id='delco-duffers-2026';
END;
$$;
REVOKE ALL ON FUNCTION public.reset_duffers_scores() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reset_duffers_scores() TO authenticated;
