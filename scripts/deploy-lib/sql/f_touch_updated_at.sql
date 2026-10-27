CREATE OR REPLACE FUNCTION deployment.f_touch_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    NEW.updated_at = now();
    -- Who: the app (studio.dml, app-engine) sets updated_by itself and has app.current_email set, so leave
    -- that alone. Only a direct SQL edit (no app context, updated_by untouched) gets the database role.
    IF NEW.updated_by IS NOT DISTINCT FROM OLD.updated_by
       AND coalesce(current_setting('app.current_email', true), '') = '' THEN
        NEW.updated_by = current_user;
    END IF;
    RETURN NEW;
END;
$function$
;

