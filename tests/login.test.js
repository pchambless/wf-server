const request = require('supertest');
const { app } = require('../server'); // Ensure this path is correct

describe('Login Endpoint', () => {
  it('should handle user login', async () => {
    const email = 'test@example.com';
    const password = 'password123'; // Use a placeholder if needed

    const response = await request(app)
      .post('/api/users/login')
      .send({ userEmail: email, password }); // Ensure this matches the expected structure

    expect(response.status).toBe(200); // Adjust based on your actual response
    expect(response.body).toHaveProperty('token'); // Adjust based on your actual response
  });
});
