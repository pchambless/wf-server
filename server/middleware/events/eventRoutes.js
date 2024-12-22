module.exports = [
  {
    "eventType": "ingrTypeDelete",
    "method": "PATCH",
    "params": "[\n  \":userID\",\n  \":ingrTypeID\"\n]",
    "path": "/api/accts/ingredient/ingrType",
    "qrySQL": "update ingredient_types\nset deleted_at = Now(),\ndeleted_by = :userID\nwhere id = :ingrTypeID",
    "parent": "/ingrType",
    "purpose": "Soft Delete Ingredient Type."
  },
  {
    "eventType": "ingrTypeEdit",
    "method": "PATCH",
    "params": "[\n  \":name\",\n  \":description\",\n  \":ingrTypeID\"\n]",
    "path": "/api/accts/ingredient/ingrType",
    "qrySQL": "update ingredient_types\nset name = :name\n, description = :description\nwhere id = :ingrTypeID",
    "parent": "/ingrType",
    "purpose": "Edit Ingredient Type"
  },
  {
    "eventType": "ingrTypeList",
    "method": "GET",
    "params": "[\n  \":acctID\"\n]",
    "path": "/api/accts/ingredient/ingrType",
    "qrySQL": "SELECT name, description, id \nFROM ingredient_types \nWHERE account_id = :acctID \nAND active = \"Y\" \nORDER BY name",
    "parent": "/ingrType",
    "purpose": "List all the ingredient types for the selected Account"
  },
  {
    "eventType": "prodTypeList",
    "method": "GET",
    "params": "[\n  \":acctID\"\n]",
    "path": "/api/accts/product/prodType",
    "qrySQL": "SELECT id, name, account_id\nfrom  product_types a\nwhere account_id = :acctID\nand active = 'Y'\norder by name",
    "parent": "/prodType",
    "purpose": "List the Prod Types"
  },
  {
    "eventType": "userAccts",
    "method": "GET",
    "params": "[\n  \":userEmail\"\n]",
    "path": "/api/users",
    "qrySQL": "select acct_id value, account_name label\nfrom   v_wf_usr_dtl a\nwhere  email = :userEmail\nORDER BY account_name",
    "parent": "/users",
    "purpose": "Get the list of Accounts the user has privelages for."
  }
];