module.exports = [
  {
    "eventType": "ingrTypeAdd",
    "method": "POST",
    "path": "/api/accts/ingredient/ingrType",
    "qrySQL": "insert into ingredient_types\n(name, description, account_id)\nVALUES\n(:name, :description, :acctID);",
    "parent": "/ingrType",
    "purpose": "Add a new Ingredient Type"
  },
  {
    "eventType": "ingrTypeEdit",
    "method": "PATCH",
    "path": "/api/accts/ingredient/ingrType",
    "qrySQL": "update ingredient_types\nset name = :name\n, description = :description\nwhere id = :ingrTypeID",
    "parent": "/ingrType",
    "purpose": "Edit Ingredient Type"
  },
  {
    "eventType": "ingrTypeList",
    "method": "GET",
    "path": "/api/accts/ingredient/ingrType",
    "qrySQL": "SELECT name, description, id \nFROM ingredient_types \nWHERE account_id = :acctID \nAND active = \"Y\" \nORDER BY name",
    "parent": "/ingrType",
    "purpose": "List all the ingredient types for the selected Account"
  },
  {
    "eventType": "ingrTypeDelete",
    "method": "SDELETE",
    "path": "/api/accts/ingredient/ingrType",
    "qrySQL": "update ingredient_types\nset deleted_at = Now(),\ndeleted_by = :userID\nwhere id = :ingrTypeID",
    "parent": "/ingrType",
    "purpose": "Soft Delete Ingredient Type."
  },
  {
    "eventType": "prodTypeList",
    "method": "GET",
    "path": "/api/accts/product/prodType",
    "qrySQL": "SELECT id, name, account_id\nfrom  product_types a\nwhere account_id = :acctID\nand active = 'Y'\norder by name",
    "parent": "/prodType",
    "purpose": "List the Prod Types"
  },
  {
    "eventType": "userAccts",
    "method": "GET",
    "path": "/api/users",
    "qrySQL": "select acct_id value, account_name label\nfrom   v_wf_usr_dtl a\nwhere  email = :userEmail\nORDER BY account_name",
    "parent": "/users",
    "purpose": "Get the list of Accounts the user has privelages for."
  }
];