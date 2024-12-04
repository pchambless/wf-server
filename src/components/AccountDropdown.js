import React from 'react';
import { useUserContext } from '../context/UserContext';

const AccountDropdown = () => {
  const { accounts, selectedAccount, setSelectedAccount } = useUserContext();

  const handleChange = (e) => {
    const selected = accounts.find(account => account.id === e.target.value);
    setSelectedAccount(selected);
  };

  return (
    <select value={selectedAccount ? selectedAccount.id : ''} onChange={handleChange} className="p-2 border rounded">
      <option value="" disabled>Select Account</option>
      {accounts.map((account) => (
        <option key={account.id} value={account.id}>{account.name}</option>
      ))}
    </select>
  );
};

export default AccountDropdown;
