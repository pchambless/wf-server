CREATE OR REPLACE VIEW api_userAccts
as
SELECT	case when c.NAME IS NULL then '' ELSE c.NAME end  acctName
,        a.first_name                         firstName
,			CONCAT(a.first_name, ' ', a.last_name)  fullName
,			case when a.role = 1 then 'Global' ELSE '' END roleID
,			case when b.is_owner then 'Owner' ELSE '' END ownerFlag
,        a.email
,			a.id												            userID
,			b.account_id									          acctID
,     b.is_owner	                            isOwner
,			cast(b.id as unsigned)						      acctUserID
,			a.default_account_id							      dfltAcctID
FROM    		whatsfresh.users a
JOIN			whatsfresh.accounts_users b
ON				a.id = b.user_id
JOIN			whatsfresh.accounts c
ON				b.account_id = c.id
where a.active = 'Y'
and   c.active = 'Y'
ORDER BY 1
,			4 DESC
, 			2
