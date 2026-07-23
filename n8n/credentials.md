# Production Credentials Manifest

Required credentials for the production n8n instance.
Workflow imports reference these by name — create them on prod before importing.

## Required Credentials

| Name | Type | Used By | Notes |
|------|------|---------|-------|
| postgres-cred | postgres | All DB-accessing workflows | Points to production postgres instance |

## Setup Notes

- Create credentials with the exact names listed above on the production n8n instance
- Workflow JSON exports reference credentials by name; mismatched names require manual remapping
- Never store actual secrets in this file or in git
