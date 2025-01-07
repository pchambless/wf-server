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
    "eventType": "userList",
    "method": "GET",
    "params": "[]",
    "parent": "0.0.1-Users",
    "qrySQL": "select *\nfrom v_userList",
    "purpose": "The list of Whatsfresh Users."
  },
  {
    "eventType": "acctList",
    "method": "GET",
    "params": "[]",
    "parent": "0.0.3-Accounts",
    "qrySQL": "select *\nfrom v_acctList",
    "purpose": "Get the list of WF Accounts"
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
    "eventType": "prodTypeEdit",
    "method": "PATCH",
    "params": "[\n  \":prodTypeName\",\n  \":userID\",\n  \":prodTypeID\"\n]",
    "parent": "0.3.2-Product Types",
    "qrySQL": "update product_types\nset name = :prodTypeName\n, updated_by = :userID\n, updated_at = now()\nwhere id = :prodTypeID",
    "purpose": "Edit a Product"
  },
  {
    "eventType": "prodTypeList",
    "method": "GET",
    "params": "[\n  \":acctID\"\n]",
    "parent": "0.3.2-Product Types",
    "qrySQL": "SELECT name, id\nfrom  product_types a\nwhere account_id = :acctID\nand active = 'Y'\norder by name",
    "purpose": "List the Prod Types"
  },
  {
    "eventType": "brndEdit",
    "method": "PATCH",
    "params": "[\n  \":brndName\",\n  \":userID\",\n  \":brndID\"\n]",
    "parent": "0.3.3-Brands",
    "qrySQL": "UPDATE brands\nset name = :brndName\nupdated_by = :userID\nupdated_at = Now()\nwhere id = :brndID",
    "purpose": "Edit the Brand name."
  },
  {
    "eventType": "brndList",
    "method": "GET",
    "params": "[\n  \":acctID\"\n]",
    "parent": "0.3.3-Brands",
    "qrySQL": "SELECT *\nfrom  v_brandList\nwhere account_id = :acctID",
    "purpose": "the List of Brands."
  },
  {
    "eventType": "ingrList",
    "method": "GET",
    "params": "[\n  \":ingrTypeID\"\n]",
    "parent": "3.1.2-Ingredients",
    "qrySQL": "select ingr_code, ingr_name, ingr_desc, dflt_meas, dflt_vndr, ingr_id\nfrom v_ingr_list\nwhere ingr_type_id = :ingrTypeID",
    "purpose": "List of Ingredients"
  },
  {
    "eventType": "prodList",
    "method": "GET",
    "params": "[\n  \":prodTypeID\"\n]",
    "parent": "3.2.1-Products",
    "qrySQL": "select prodCode, prodName, prodDesc, bestByDays, location, prodMeas, prodID\nfrom v_prodList\nwhere prodTypeID = :prodTypeID\norder by prodName",
    "purpose": "GET the list of Products for a Product Type"
  }
];