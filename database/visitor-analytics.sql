CREATE TABLE public.duffers_visitor_events (
id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
visitor_id uuid NOT NULL,
kind text NOT NULL CHECK (kind IN ('visit','tab')),
page text NOT NULL CHECK (page IN ('dashboard','live','thursday','scats','par3','leaderboards','players','rules','matchups','scoring','history','login')),
occurred_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.duffers_visitor_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.duffers_visitor_events FROM PUBLIC,anon,authenticated;
GRANT INSERT(visitor_id,kind,page) ON public.duffers_visitor_events TO anon,authenticated;
GRANT SELECT ON public.duffers_visitor_events TO authenticated;
CREATE POLICY record_visit_only ON public.duffers_visitor_events FOR INSERT TO anon,authenticated
WITH CHECK (occurred_at=now());
CREATE POLICY rocco_read_visitors ON public.duffers_visitor_events FOR SELECT TO authenticated
USING ((SELECT auth.uid())='e30420bc-c0c6-4b61-9498-333623e8db47'::uuid);
CREATE INDEX duffers_visitor_events_date_idx ON public.duffers_visitor_events(occurred_at);
CREATE FUNCTION public.duffers_visitor_report()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=''
AS $report$
DECLARE result jsonb;
BEGIN
IF auth.uid() IS DISTINCT FROM 'e30420bc-c0c6-4b61-9498-333623e8db47'::uuid THEN
RAISE EXCEPTION 'Only the site owner can view visitor statistics' USING ERRCODE='42501';
END IF;
SELECT jsonb_build_object(
'started_at',min(occurred_at),
'visitors',count(DISTINCT visitor_id),
'page_views',count(*) FILTER(WHERE kind='visit'),
'today_visitors',count(DISTINCT visitor_id) FILTER(WHERE (occurred_at AT TIME ZONE 'America/New_York')::date=(now() AT TIME ZONE 'America/New_York')::date),
'today_views',count(*) FILTER(WHERE kind='visit' AND (occurred_at AT TIME ZONE 'America/New_York')::date=(now() AT TIME ZONE 'America/New_York')::date)
) INTO result FROM public.duffers_visitor_events;
RETURN result||jsonb_build_object(
'daily',coalesce((SELECT jsonb_agg(to_jsonb(d) ORDER BY d.day DESC) FROM (
SELECT (occurred_at AT TIME ZONE 'America/New_York')::date AS day,count(DISTINCT visitor_id) AS visitors,count(*) FILTER(WHERE kind='visit') AS page_views
FROM public.duffers_visitor_events
WHERE occurred_at>=((now() AT TIME ZONE 'America/New_York')::date-13)::timestamp AT TIME ZONE 'America/New_York'
GROUP BY 1) d),'[]'::jsonb),
'tabs',coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.views DESC,t.page) FROM (
SELECT page,count(*) AS views FROM public.duffers_visitor_events WHERE kind='tab' GROUP BY page) t),'[]'::jsonb));
END;
$report$;
REVOKE ALL ON FUNCTION public.duffers_visitor_report() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.duffers_visitor_report() TO authenticated;
NOTIFY pgrst,'reload schema';