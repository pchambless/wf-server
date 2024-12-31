module.exports = [
  {
    "eventType": "userAccts",
    "method": "GET",
    "params": "[\n  \":userEmail\"\n]",
    "parent": "0.0.1-Users",
    "qrySQL": "select acct_id, account_name\nfrom   v_wf_usr_dtl a\nwhere  email = :userEmail\nORDER BY account_name",
    "purpose": "Get the list of Accounts the user has privelages for."
  },
  {
    "eventType": "ingrTypeDelete",
    "method": "DELETE",
    "params": "[\n  \":ingrTypeID\"\n]",
    "parent": "0.3.1-Ingredient Types",
    "qrySQL": "DELETE \nfrom ingredient_types\nwhere id = :ingrTypeID",
    "purpose": "Hard delete an Ingredient Type"
  },
  {
    "eventType": "ingrTypeEdit",
    "method": "PATCH",
    "params": "[\n  \":ingrTypeName\",\n  \":ingrTypeDesc\",\n  \":ingrTypeID\"\n]",
    "parent": "0.3.1-Ingredient Types",
    "qrySQL": "update ingredient_types\nset name = :ingrTypeName\n, description = :ingrTypeDesc\nwhere id = :ingrTypeID",
    "purpose": "Edit Ingredient Type"
  },
  {
    "eventType": "ingrTypeList",
    "method": "GET",
    "params": "[\n  \":acctID\"\n]",
    "parent": "0.3.1-Ingredient Types",
    "qrySQL": "SELECT name, description, id \nFROM ingredient_types \nWHERE account_id = :acctID \nAND active = \"Y\" \nORDER BY name",
    "purpose": "List all the ingredient types for the selected Account"
  },
  {
    "eventType": "ingrTypeSDelete",
    "method": "PATCH",
    "params": "[\n  \":userID\",\n  \":ingrTypeID\"\n]",
    "parent": "0.3.1-Ingredient Types",
    "qrySQL": "update ingredient_types\nset deleted_at = Now(),\ndeleted_by = :userID\nwhere id = :ingrTypeID",
    "purpose": "Soft Delete Ingredient Type."
  },
  {
    "eventType": "prodTypeList",
    "method": "GET",
    "params": "[\n  \":acctID\"\n]",
    "parent": "0.3.2-Product Types",
    "qrySQL": "SELECT name, id\nfrom  product_types a\nwhere account_id = :acctID\nand active = 'Y'\norder by name",
    "purpose": "List the Prod Types"
  }
];