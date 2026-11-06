import { callWorkflow } from './n8nClient.js';
import { escSqlString } from './sqlEscape.js';

// Account scoping reads account_id from the context store, and several routes copy request
// values into it (or pass them straight to a workflow). The browser supplies those values, so
// an account_id is only honoured for a user who belongs to that account, or is global staff
// (role 1). Anything else is refused before it is stored or used (task 785).
export async function userMayUseAccount(email, accountId) {
  const id = Number(accountId);
  if (!Number.isInteger(id) || id <= 0) return false;

  const result = await callWorkflow('server-query', {
    query: `SELECT 1 AS ok FROM whatsfresh.users u
            WHERE lower(u.email) = lower(${escSqlString(email)}) AND u.deleted_at IS NULL
              AND (u.role = 1 OR EXISTS (
                SELECT 1 FROM whatsfresh.accounts_users au
                WHERE au.user_id = u.id AND au.account_id = ${id} AND au.deleted_at IS NULL))`,
    params: {},
    source: 'account-guard'
  });
  const row = Array.isArray(result) ? result[0] : result;
  return row?.ok === 1;
}

const isSet = (v) => v !== null && v !== undefined && v !== '' && v !== 'null';

// True when `values` (a request body or setvals map) carries no account_id, or one the user may
// use. Key match ignores case. A lookup failure throws, so the caller fails closed.
export async function accountValuesAllowed(email, values) {
  if (!values || typeof values !== 'object') return true;
  for (const [key, val] of Object.entries(values)) {
    if (key.toLowerCase() === 'account_id' && isSet(val)) {
      if (!(await userMayUseAccount(email, val))) return false;
    }
  }
  return true;
}
