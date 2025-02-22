const express = require('express');
const morgan = require('morgan');
const cors = require('cors');
const dotenv = require('dotenv');
const userLogin = require('./controller/userLogin'); // Import the userLogin controller
const codeName = `[app.js] `;

dotenv.config();

const app = express();
const port = process.env.PORT || 3001;

app.use(morgan('combined'));
app.use(cors({
  origin: ['http://localhost:3000',
  'https://972d-2600-1700-8ea6-c000-8001-ba31-1a04-7686.ngrok-free.app']
}));
app.use(express.json());

console.log(codeName, 'entered app.js');

// Log middleware to track initialization
app.use((req, res, next) => {
  console.log(codeName, `Processing ${req.method} ${req.path}`);
  next();
});

// Define the GET route for login
app.get('/api/auth/login', userLogin); // Ensure this line is present

// Remove the server listening part
// app.listen(port, () => {
//   console.log(`Server running on port ${port}`);
// });

module.exports = {
  app,
  port
};
