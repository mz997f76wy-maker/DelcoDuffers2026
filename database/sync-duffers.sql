CREATE OR REPLACE FUNCTION public.sync_duffers_changes(p_tournament_id text, p_known jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $sync$
WITH raw AS MATERIALIZED (
SELECT 'tournament_players'::text AS table_name, jsonb_build_array(t.id)::text AS row_key, to_jsonb(t) AS row_data FROM public.tournament_players t WHERE t.tournament_id=p_tournament_id
UNION ALL
SELECT 'tournament_matchups'::text AS table_name, jsonb_build_array(t.round_no,t.match_no)::text AS row_key, to_jsonb(t) AS row_data FROM public.tournament_matchups t WHERE t.tournament_id=p_tournament_id
UNION ALL
SELECT 'tournament_scores'::text AS table_name, jsonb_build_array(t.round_no,t.match_no,t.hole,t.scorer_key)::text AS row_key, to_jsonb(t) AS row_data FROM public.tournament_scores t WHERE t.tournament_id=p_tournament_id
UNION ALL
SELECT 'tournament_results'::text AS table_name, jsonb_build_array(t.round_no,t.match_no)::text AS row_key, to_jsonb(t) AS row_data FROM public.tournament_results t WHERE t.tournament_id=p_tournament_id
UNION ALL
SELECT 'tournament_round_settings'::text AS table_name, jsonb_build_array(t.round_no)::text AS row_key, to_jsonb(t) AS row_data FROM public.tournament_round_settings t WHERE t.tournament_id=p_tournament_id
UNION ALL
SELECT 'tournament_par3_results'::text AS table_name, jsonb_build_array(t.round_no,t.hole)::text AS row_key, to_jsonb(t) AS row_data FROM public.tournament_par3_results t WHERE t.tournament_id=p_tournament_id
UNION ALL
SELECT 'tournament_live_status'::text AS table_name, jsonb_build_array(t.round_no,t.match_no,t.hole)::text AS row_key, to_jsonb(t) AS row_data FROM public.tournament_live_status t WHERE t.tournament_id=p_tournament_id
UNION ALL
SELECT 'tournament_thursday_scores'::text AS table_name, jsonb_build_array(t.group_no,t.player_no,t.hole)::text AS row_key, to_jsonb(t) AS row_data FROM public.tournament_thursday_scores t WHERE t.tournament_id=p_tournament_id
), grouped AS (
 SELECT table_name, get_byte(decode(md5(row_key),'hex'),0)%32 AS bucket,
 jsonb_agg(row_data ORDER BY row_key) AS rows
 FROM raw GROUP BY table_name, get_byte(decode(md5(row_key),'hex'),0)%32
), batches AS (
 SELECT names.table_name, b.bucket, coalesce(g.rows,'[]'::jsonb) AS rows
 FROM unnest(ARRAY['tournament_players','tournament_matchups','tournament_scores','tournament_results','tournament_round_settings','tournament_par3_results','tournament_live_status','tournament_thursday_scores']) names(table_name)
 CROSS JOIN generate_series(0,31) b(bucket)
 LEFT JOIN grouped g ON g.table_name=names.table_name AND g.bucket=b.bucket
), hashed AS (
 SELECT *, table_name||':'||bucket::text AS key, md5(rows::text) AS hash FROM batches
)
SELECT jsonb_build_object('patches',coalesce(jsonb_agg(jsonb_build_object('key',key,'table',table_name,'bucket',bucket,'hash',hash,'rows',rows))
FILTER (WHERE hash IS DISTINCT FROM coalesce(p_known->>key,md5('[]'))),'[]'::jsonb))
FROM hashed;
$sync$;
REVOKE ALL ON FUNCTION public.sync_duffers_changes(text,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.sync_duffers_changes(text,jsonb) TO anon,authenticated;
NOTIFY pgrst, 'reload schema';