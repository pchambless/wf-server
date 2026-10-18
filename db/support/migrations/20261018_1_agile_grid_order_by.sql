-- Task 599: the support agile board lists old Done tasks first when Agile Apps = All.
-- agile_hier_grid's hydrate joins agile.ft_agile_sprint(...) (which orders by its own sort_path) to agile.vw_task_deployed
-- but has no ORDER BY of its own. With 470 rows the planner chooses a hash join that returns the rows that have deployment
-- records first, in task_id order, and the App/Epic/Sprint headers after. Order explicitly by the id chain in f.path
-- ('52.6.13.50'); an integer array sorts numerically, plain text would put '10' before '5'.
-- Idempotent: does nothing if the hydrate already has an ORDER BY. Run against the dev n8n database (schema support).
UPDATE support.html_templates
   SET hydrate = rtrim(hydrate, E' \n') || E'\norder by string_to_array(f.path, ''.'')::int[]',
       updated_at = now(), updated_by = 'claude'
 WHERE id = 2 AND name = 'agile_hier_grid' AND hydrate NOT ILIKE '%order by%';
