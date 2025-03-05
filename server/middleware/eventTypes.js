module.exports = [
  {
    "eventID": 61,
    "eventType": "acctList",
    "method": "GET",
    "qrySQL": "SELECT *\nFROM api_wf.acctList\nORDER BY acctName",
    "params": "[]",
    "purpose": "Get the list of WF Accounts"
  },
  {
    "eventID": 98,
    "eventType": "apiEventList",
    "method": "GET",
    "qrySQL": "SELECT * \nFROM api_wf.apiEventList",
    "params": "[]",
    "purpose": "This list of all the Events used in the whatsfresh App."
  },
  {
    "eventID": 96,
    "eventType": "apiPageConfigList",
    "method": "GET",
    "qrySQL": "SELECT * FROM api_wf.apiPageConfigList",
    "params": "[]",
    "purpose": "This list of the pageConfigs which contain data for page configurations for the Whatsfresh Pages."
  },
  {
    "eventID": 4,
    "eventType": "brndList",
    "method": "GET",
    "qrySQL": "SELECT *\nFROM api_wf.brndList\nwhere acctID = :acctID\nORDER BY brndName",
    "params": "[\n  \":acctID\"\n]",
    "purpose": "the List of Brands."
  },
  {
    "eventID": 69,
    "eventType": "ingrBtchList",
    "method": "GET",
    "qrySQL": "SELECT *\nFROM api_wf.ingrBtchList\nwhere  ingrID = :ingrID\nLIMIT 25",
    "params": "[\n  \":ingrID\"\n]",
    "purpose": "List the selected Ingredient's Batches"
  },
  {
    "eventID": 81,
    "eventType": "ingrList",
    "method": "GET",
    "qrySQL": "SELECT *\nFROM api_wf.ingrList\nwhere ingrTypeID = :ingrTypeID",
    "params": "[\n  \":ingrTypeID\"\n]",
    "purpose": "List of Ingredients"
  },
  {
    "eventID": 14,
    "eventType": "ingrTypeList",
    "method": "GET",
    "qrySQL": "SELECT *\nFROM api_wf.ingrTypeList\nWHERE acctID = :acctID \nORDER BY ingrTypeName",
    "params": "[\n  \":acctID\"\n]",
    "purpose": "List all the ingredient types for the selected Account"
  },
  {
    "eventID": 99,
    "eventType": "measList",
    "method": "GET",
    "qrySQL": "SELECT *\nFROM api_wf.measList\nORDER BY name",
    "params": "[]",
    "purpose": "Globally available list of measure units"
  },
  {
    "eventID": 100,
    "eventType": "pageList",
    "method": "GET",
    "qrySQL": "SELECT * from api_wf.pageList",
    "params": "[]",
    "purpose": "The list of Whatsfresh Pages."
  },
  {
    "eventID": 101,
    "eventType": "prodBtchList",
    "method": "GET",
    "qrySQL": "SELECT * FROM api_wf.prodBtchList\nWHERE prodID = :prodID\nLIMIT 25",
    "params": "[\n  \":prodID\"\n]",
    "purpose": "Get the List of Product Batches."
  },
  {
    "eventID": 94,
    "eventType": "prodList",
    "method": "GET",
    "qrySQL": "select *\nfrom api_wf.prodList\nwhere prodTypeID = :prodTypeID\norder by prodName",
    "params": "[\n  \":prodTypeID\"\n]",
    "purpose": "GET the list of Products for a Product Type"
  },
  {
    "eventID": 31,
    "eventType": "prodTypeList",
    "method": "GET",
    "qrySQL": "SELECT *\nfrom  api_wf.prodTypeList\nwhere acctID = :acctID\norder by prodTypeName",
    "params": "[\n  \":acctID\"\n]",
    "purpose": "List the Prod Types"
  },
  {
    "eventID": 27,
    "eventType": "rcpeList",
    "method": "GET",
    "qrySQL": "",
    "params": "[]",
    "purpose": "List the Recipe Ingredients for a selected Product."
  },
  {
    "eventID": 95,
    "eventType": "taskList",
    "method": "GET",
    "qrySQL": "SELECT  *\nFROM api_wf.taskList\nWHERE prodTypeID = :prodTypeID\nORDER BY taskOrder",
    "params": "[\n  \":prodTypeID\"\n]",
    "purpose": "Fetch tasks associated to a Product Type"
  },
  {
    "eventID": 86,
    "eventType": "userAcctList",
    "method": "GET",
    "qrySQL": "SELECT *\nFROM api_wf.userAcctList\nWHERE userID = :userID\nORDER BY acctName",
    "params": "[\n  \":userID\"\n]",
    "purpose": "Get the list of Accounts the user has privelages for."
  },
  {
    "eventID": 37,
    "eventType": "userList",
    "method": "GET",
    "qrySQL": "select *\nfrom api_wf.userList\norder by lastName",
    "params": "[]",
    "purpose": "The list of Whatsfresh Users."
  },
  {
    "eventID": 87,
    "eventType": "userLogin",
    "method": "GET",
    "qrySQL": "select *, :enteredPassword\nfrom api_wf.userList\nwhere userEmail = :userEmail",
    "params": "[\n  \":enteredPassword\",\n  \":userEmail\"\n]",
    "purpose": "Login for User."
  },
  {
    "eventID": 40,
    "eventType": "vndrList",
    "method": "GET",
    "qrySQL": "SELECT *\nFROM api_wf.vndrList\nWHERE acctID = :acctID\nORDER BY vndrName",
    "params": "[\n  \":acctID\"\n]",
    "purpose": "Get the List of Vendors"
  },
  {
    "eventID": 43,
    "eventType": "wrkrList",
    "method": "GET",
    "qrySQL": "SELECT *\nFROM api_wf.wrkrList\nWHERE acctID = :acctID\nORDER BY wrkrName",
    "params": "[\n  \":acctID\"\n]",
    "purpose": "List of Account Workers."
  }
];