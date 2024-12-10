import React from 'react';
import AccountDropdown from '../components/AccountDropdown';
import { useUserContext } from '../context/UserContext';
import logo from '../assets/wf-icon.png';
import { useNavigate } from 'react-router-dom';

const Main = () => {
  const { setUserEmail, setEventTypes } = useUserContext();
  const navigate = useNavigate();

  const handleLogout = () => {
    setUserEmail('');
    setEventTypes([]);
    localStorage.clear();
    navigate('/');
  };

  return (
    <div className="min-h-screen">
      <header className="flex items-center justify-between p-4 bg-gray-100 border-b">
        <div className="flex items-center">
          <img src={logo} alt="Whatsfresh Logo" className="w-12 h-12 mr-2" />
          <h1 className="text-2xl font-bold">Page Name</h1>
        </div>
        <div className="flex items-center">
          <AccountDropdown />
          <button onClick={handleLogout} className="ml-4 px-4 py-2 text-white bg-red-600 rounded hover:bg-red-700">
            Logout
          </button>
        </div>
      </header>
      <nav className="p-4 bg-gray-200">
        {/* AppNavMenu with navigation links */}
      </nav>
      <main className="p-4">
        {/* Dynamic content based on navigation */}
      </main>
    </div>
  );
};

export default Main;
