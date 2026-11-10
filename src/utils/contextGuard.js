// Identity context keys are server-owned (task 845): login writes them from the verified user, and the browser can
// neither set nor clear them through /api/actions or /api/hydrate. Otherwise a request could change who it is to the
// database: userEmail scopes the account dropdown, firstName stamps created_by/updated_by. account_id stays a
// browser-chosen value, checked separately by accountGuard (task 785).
const SERVER_OWNED = new Set(['useremail', 'userid', 'firstname', 'lastname', 'role_id']);

export const isServerOwnedKey = (key) => SERVER_OWNED.has(String(key || '').toLowerCase());

// Drop server-owned keys from a list of setvals entries ({ param_name, param_val }) or of key names.
export const withoutServerOwned = (items) =>
  items.filter((item) => !isServerOwnedKey(typeof item === 'string' ? item : item?.param_name));

// The identity values login stores for a user; also used to restore them after a browser-requested clear_all.
export function identityContextVals(email, user = {}, accountId) {
  return [
    { param_name: 'userEmail', param_val: email },
    { param_name: 'userID', param_val: user.user_id },
    { param_name: 'account_id', param_val: accountId },
    { param_name: 'firstName', param_val: user.first_name },
    { param_name: 'lastName', param_val: user.last_name },
    { param_name: 'role_id', param_val: user.role_id }
  ]
    .filter((v) => v.param_val !== null && v.param_val !== undefined && v.param_val !== '')
    .map((v) => ({ param_name: v.param_name, param_val: String(v.param_val) }));
}
