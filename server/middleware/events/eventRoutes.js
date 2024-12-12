module.exports = [
  {
    "eventType": "ingrTypeAdd",
    "method": "POST",
    "path": "/api/accts/ingredient/ingrType",
    "params": "",
    "bodyCols": "{name}\n{description}\n{acctID}",
    "qrySQL": "insert into product_types\n(name, description, account_id)\nVALUES\n(?,?,?);",
    "parent": "/ingrType"
  },
  {
    "eventType": "ingrTypeEdit",
    "method": "PATCH",
    "path": "/api/accts/ingredient/ingrType",
    "params": "{ingrTypeID}",
    "bodyCols": "{name}\n{description}",
    "qrySQL": "update ingredient_types\nset name = ?\n, description = ?\nwhere id = ?",
    "parent": "/ingrType"
  },
  {
    "eventType": "ingrTypeList",
    "method": "GET",
    "path": "/api/accts/ingredient/ingrType",
    "params": "{acctID}",
    "bodyCols": "",
    "qrySQL": "SELECT name, description, id \nFROM ingredient_types \nWHERE account_id = ? \nAND active = \"Y\" \nORDER BY name",
    "parent": "/ingrType"
  },
  {
    "eventType": "ingrTypeDelete",
    "method": "SDELETE",
    "path": "/api/accts/ingredient/ingrType",
    "params": "{ingrTypeID}",
    "bodyCols": "",
    "qrySQL": "update ingredient_types\nset deleted_at = Now(),\ndeleted_by = ?\nwhere id = ?",
    "parent": "/ingrType"
  },
  {
    "eventType": "prodTypeList",
    "method": "GET",
    "path": "/api/accts/product/prodType",
    "params": "{acctID}",
    "bodyCols": "",
    "qrySQL": "SELECT id, name, account_id\nfrom  product_types a\nwhere account_id = ?\nand active = 'Y'\norder by name",
    "parent": "/prodType"
  },
  {
    "eventType": "userAccts",
    "method": "GET",
    "path": "/api/users",
    "params": "{userEmail}",
    "bodyCols": "",
    "qrySQL": "select acct_id value, account_name label\nfrom   v_wf_usr_dtl a\nwhere  email = ?\nORDER BY account_name",
    "parent": "/users"
  }
];