const axios = require('axios');

const apiClient = axios.create({
  baseURL: 'http://localhost:3001',
  timeout: 1000,
  headers: { 'Content-Type': 'application/json' }
});

apiClient.interceptors.request.use(
  config => {
    console.log('[apiClient] Request:', config);
    return config;
  },
  error => Promise.reject(error)
);

apiClient.interceptors.response.use(
  response => {
    console.log('[apiClient] Response:', response);
    return response;
  },
  error => {
    console.error('[apiClient] Response Error:', error);
    return Promise.reject(error);
  }
);

module.exports = apiClient;
