// A plain email address: one @, a dot in the domain, no spaces, quotes, backslashes, angle brackets,
// parentheses or control characters (task 783). The session email is pasted into n8n workflows, so it must
// never carry SQL or HTML metacharacters, even where those are legal in RFC 5322.
const EMAIL_RE = /^[^\s@'"`\\<>()\x00-\x1f\x7f]+@[^\s@'"`\\<>()\x00-\x1f\x7f]+\.[^\s@'"`\\<>()\x00-\x1f\x7f]+$/;

export function normalizeEmail(email) {
  return typeof email === 'string' ? email.trim() : '';
}

export function isPlainEmail(email) {
  return typeof email === 'string' && email.length <= 254 && EMAIL_RE.test(email);
}
