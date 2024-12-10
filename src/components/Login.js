import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import ProductForm from '../components/ProductForm';
import { useUserContext } from '../context/UserContext';
import logo from '../assets/wf-icon.png';

const Login = () => {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const { setUserEmail, setEventTypes, setAccounts, setSelectedAccount } = useUserContext();
  const navigate = useNavigate();

  const handleLogin = async (e) => {
    e.preventDefault();
    console.log('Email:', email);
    console.log('Password:', password);

    try {
      const response = await fetch('http://localhost:3001/login', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ email, password }),
      });

      if (response.ok) {
        const data = await response.json();
        setUserEmail(email);

        // Fetch eventTypes and accounts data from the server
        const [eventTypesResponse, accountsResponse] = await Promise.all([
          fetch('/api/eventTypes'),
          fetch(`/api/accounts?email=${email}`),
        ]);

        const [eventTypesData, accountsData] = await Promise.all([
          eventTypesResponse.json(),
          accountsResponse.json(),
        ]);

        setEventTypes(eventTypesData);
        setAccounts(accountsData);

        // Default to the first account if there's only one
        if (accountsData.length === 1) {
          setSelectedAccount(accountsData[0]);
        }

        localStorage.setItem('eventTypes', JSON.stringify(eventTypesData));
        navigate('/main');
      } else {
        const errorText = await response.text();
        alert(`Login failed: ${errorText}`);
      }
    } catch (error) {
      console.error('Login error:', error);
      alert('An error occurred while logging in. Please try again.');
    }
  };

  return (
    <div className="flex flex-col items-center justify-center min-h-screen bg-product-bg">
      <div className="flex items-center mb-6">
        <img src={logo} alt="Whatsfresh Logo" className="w-8 h-8 mr-2" />
        <h2 className="text-3xl font-bold text-gray-800">Whatsfresh Today?</h2>
      </div>
      <ProductForm onSubmit={handleLogin}>
        <div className="mb-4">
          <label htmlFor="email" className="block mb-1 text-sm font-medium text-gray-700">Email:</label>
          <input
            type="email"
            id="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className="w-full px-4 py-2 text-sm border rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            required
          />
        </div>
        <div className="mb-6">
          <label htmlFor="password" className="block mb-1 text-sm font-medium text-gray-700">Password:</label>
          <input
            type="password"
            id="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            className="w-full px-4 py-2 text-sm border rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            required
          />
        </div>
        <button type="submit" className="w-full px-4 py-2 text-white bg-blue-600 rounded-md hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2">Login</button>
      </ProductForm>
    </div>
  );
};

export default Login;
