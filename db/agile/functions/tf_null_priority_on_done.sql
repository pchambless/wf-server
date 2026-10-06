CREATE OR REPLACE FUNCTION agile.tf_null_priority_on_done()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.status = 'Done' THEN
    NEW.priority := NULL;
  END IF;
  RETURN NEW;
END;
$function$
;

