CREATE OR REPLACE FUNCTION whatsfresh.api_brands()
 RETURNS TABLE(id integer, account_id integer, batch_cnt integer, name text, url text, comments text)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT  a.id,
          a.account_id,
          coalesce(b.batch_cnt,0)::int,
          a.name,
          a.url,
          a.comments
  FROM whatsfresh.brands a
  left join
  (select brand_id, count(*) batch_cnt
	from whatsfresh.batches a
	where a.entity_kind = 'Shop'
	group by brand_id
	) b
	ON a.id = b.brand_id
  WHERE (a.deleted_at IS NULL
         OR a.id = whatsfresh.c_getval('brand_id')::int
         OR a.id::text = current_setting('whatsfresh.dd_preserve_id', true))
    AND a.account_id IN (whatsfresh.c_getval('account_id')::int, 0)
  ORDER BY batch_cnt desc, a.name
$function$
;

