CREATE OR REPLACE FUNCTION deployment.f_target_sequence_resync(p_conn text, p_schema text, p_table text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_seq   record;
  v_new   bigint;
BEGIN
  FOR v_seq IN
    SELECT sn.nspname AS seq_schema, s.relname AS seq_name, a.attname AS col_name
      FROM pg_depend d
      JOIN pg_class s ON s.oid = d.objid AND s.relkind = 'S'
      JOIN pg_namespace sn ON sn.oid = s.relnamespace
      JOIN pg_class t ON t.oid = d.refobjid
      JOIN pg_namespace tn ON tn.oid = t.relnamespace
      JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = d.refobjsubid
     WHERE tn.nspname = p_schema AND t.relname = p_table AND d.deptype IN ('a', 'i')
  LOOP
    SELECT v INTO v_new
      FROM dblink(p_conn, format('SELECT setval(%L, COALESCE((SELECT MAX(%I) FROM %I.%I), 1))',
                                 v_seq.seq_schema || '.' || v_seq.seq_name, v_seq.col_name, p_schema, p_table)) AS t(v bigint);
  END LOOP;
END
$function$
;

