export function escSqlString(val) {
  return val ? `'${val.replace(/'/g, "''")}'` : 'NULL';
}
