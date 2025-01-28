module.exports = [
  {
    "eventType": "userAccts",
    "method": "GET",
    "params": "[\n  \":userEmail\"\n]",
    "parent": "0.0.1-Users",
    "qrySQL": "select acctID, acctName\nfrom   api_wf.userAccts\nwhere  userEmail = :userEmail\nORDER BY acctName",
    "purpose": "Get the list of Accounts the user has privelages for."
  },
  {
    "eventType": "userList",
    "method": "GET",
    "params": "[]",
    "parent": "0.0.1-Users",
    "qrySQL": "select *\nfrom api_wf.userList",
    "purpose": "The list of Whatsfresh Users."
  },
  {
    "eventType": "acctList",
    "method": "GET",
    "params": "[]",
    "parent": "0.0.3-Accounts",
    "qrySQL": "select *\nfrom api_wf.acctList",
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
    "qrySQL": "SELECT *\nFROM api_wf.ingrTypeList \nWHERE acctID = :acctID \nORDER BY ingrTypeName",
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
    "qrySQL": "SELECT *\nfrom  api_wf.prodTypeList a\nwhere acctID = :acctID\norder by prodTypeName",
    "purpose": "List the Prod Types"
  },
  {
    "eventType": "brndEdit",
    "method": "PATCH",
    "params": "[\n  \":brndName\",\n  \":userID\",\n  \":brndID\"\n]",
    "parent": "0.3.3-Brands",
    "qrySQL": "UPDATE brands\nset name = :brndName,\nupdated_by = :userID,\nupdated_at = Now()\nwhere id = :brndID",
    "purpose": "Edit the Brand name."
  },
  {
    "eventType": "brndList",
    "method": "GET",
    "params": "[\n  \":acctID\"\n]",
    "parent": "0.3.3-Brands",
    "qrySQL": "SELECT *\nfrom  api_wf.brndList\nwhere acctID = :acctID",
    "purpose": "the List of Brands."
  },
  {
    "eventType": "ingrList",
    "method": "GET",
    "params": "[\n  \":ingrTypeID\"\n]",
    "parent": "3.1.2-Ingredients",
    "qrySQL": "select *\nfrom api_wf.ingrList\nwhere ingrTypeID = :ingrTypeID",
    "purpose": "List of Ingredients"
  },
  {
    "eventType": "prodList",
    "method": "GET",
    "params": "[\n  \":prodTypeID\"\n]",
    "parent": "3.2.1-Products",
    "qrySQL": "select *\nfrom api_wf.prodList\nwhere prodTypeID = :prodTypeID\norder by prodName",
    "purpose": "GET the list of Products for a Product Type"
  }
];