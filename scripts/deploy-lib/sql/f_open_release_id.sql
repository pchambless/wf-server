CREATE OR REPLACE FUNCTION deployment.f_open_release_id()
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
    SELECT r.id
      FROM agile.releases r
     WHERE r.deleted_at IS NULL AND r.kind <> 'backlog'
       AND NOT EXISTS (SELECT 1
                         FROM deployment.deployments d
                         JOIN deployment.deployment_runs x ON x.deployment_id = d.id
                         JOIN deployment.environments e ON e.id = d.environment_id
                        WHERE d.release_id = r.id AND e.name = 'prod' AND NOT x.dry_run
                          AND x.status = 'succeeded' AND x.finished_at IS NOT NULL)
     ORDER BY r.target_date, r.id
     LIMIT 1
$function$
;

