CREATE OR REPLACE FUNCTION agile.tf_session_startup()
 RETURNS TABLE(id integer, path text, page text, status text, description text)
 LANGUAGE sql
 STABLE
AS $function$ SELECT h.id, h.path, h.page, h.status, h.description FROM agile.ft_agile_sprint(58) h WHERE h.status IN ('In Progress', 'In progress', 'To Do') $function$
;
