const express = require('express');
const morgan = require('morgan');
const cors = require('cors');
const dotenv = require('dotenv');

dotenv.config();

const app = express();
const port = process.env.PORT || 3001;

app.use(morgan('combined'));
app.use(cors({
  origin: 'http://localhost:3000',
}));
app.use(express.json());

console.log('[app.js] entered app.js');

module.exports = {
  app,
  port
};
