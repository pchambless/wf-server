# Page Components Schema Cleanup

**Date:** 2026-04-10  
**Author:** Paul  
**Status:** Proposed  

## Summary

Cleaned up `studio.page_components` table to remove legacy columns from the hierarchical component model. The new slot-first architecture doesn't require these fields.

## Removed Columns

- **parent_id** — Tree hierarchy replaced by slot-based composition (`slot_name`)
- **style** — CSS styling now comes from `html_templates`, not instance overrides
- **title** — Display titles are handled by templates
- **description** — Metadata/documentation belongs in template descriptions
- **active** — Replaced with soft delete pattern (`deleted_at IS NULL`)

## Rationale

The Studio schema was originally designed around a hierarchical component tree where:
- Components could nest via `parent_id`
- Each instance had its own styling and metadata

The current architecture (v1) is **slot-first**:
- Layout templates define named slots: `{{slot:user_accounts_dd}}`
- `page_components` places templates into those slots via `slot_name`
- No nesting needed — composition happens at the template level
- CSS is template-level; styling consistency comes from the design system, not instance overrides

## Queries Updated

Any queries on `page_components` should now filter active rows with:
```sql
WHERE deleted_at IS NULL
```

Instead of:
```sql
WHERE active = true
```

## Migration

Run: `migrations/20260410_cleanup_page_components_schema.sql`

## Affected Code

None — pageRenderer and related code don't reference these columns.

## Schema After Cleanup

| Column | Type | Notes |
|--------|------|-------|
| id | int | PK |
| page_id | int | FK → page_registry |
| comp_name | string | Instance name |
| html_template_id | int | FK → html_templates |
| slot_name | string | Which slot this fills |
| order | int | Render order |
| deleted_at | timestamp | Soft delete marker |
| created_at | timestamp | |
| updated_at | timestamp | |
