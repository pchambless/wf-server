const express = require('express');
const morgan = require('morgan');
const cors = require('cors');
const dotenv = require('dotenv');
const path = require('path');
const codeName = `[${path.basename(__filename)}] `;

dotenv.config();

const app = express();
const port = process.env.PORT || 3001;

app.use(morgan('combined'));
app.use(cors({
  origin: 'http://localhost:3000',
}));
app.use(express.json());

console.log(codeName, 'entered app.js');

// Log middleware to track initialization
app.use((req, res, next) => {
  console.log(codeName, `Processing ${req.method} ${req.path}`);
  next();
});

module.exports = {
  app,
  port
};
