-- Shared SQL scanner for the system map. Returns every schema-qualified name in a SQL text,
-- with verb 'writes' when an insert/update/delete/merge/truncate targets it, else 'ref'.
-- Callers resolve (scope, obj) against sys_node: relations -> reads/writes, functions -> calls.
-- Misses unqualified names and SQL built at run time (format %I / EXECUTE).
CREATE OR REPLACE FUNCTION deployment.f_sys_sql_refs(p_sql text)
RETURNS TABLE (scope text, obj text, verb text) LANGUAGE sql IMMUTABLE AS $body$
WITH s AS (SELECT regexp_replace(lower(coalesce(p_sql, '')), '--[^\n]*', '', 'g') AS src)
SELECT DISTINCT m[2], m[3], 'writes'
  FROM s, regexp_matches(s.src, '(insert\s+into|update|delete\s+from|merge\s+into|truncate)\s+(?:only\s+)?"?([a-z_][a-z0-9_]*)"?\."?([a-z_][a-z0-9_]*)', 'g') m
UNION
SELECT DISTINCT m[1], m[2], 'ref'
  FROM s, regexp_matches(s.src, '"?([a-z_][a-z0-9_]*)"?\."?([a-z_][a-z0-9_]*)', 'g') m
$body$;
