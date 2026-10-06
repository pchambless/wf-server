CREATE OR REPLACE FUNCTION deployment.f_releases_delete_guard()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF OLD.status <> 'pending' THEN
        RAISE EXCEPTION 'cannot delete release % - status is %, only pending releases can be deleted', OLD.id, OLD.status;
    END IF;
    RETURN OLD;
END;
$function$
;

