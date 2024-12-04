const express = require('express');
const cors = require('cors');
const bodyParser = require('body-parser');
require('dotenv').config();

const app = express();
app.use(cors());
app.use(bodyParser.json());

// Load the database connection
const db = require('./api/db');

// Import routes
const apiEventsRoutes = require('./api/events/eventTypes');

app.use('/api/events', apiEventsRoutes);

// Define a simple route to test the DB connection
app.get('/api/test-connection', (req, res) => {
  db.query('SELECT 1', (err, results) => {
    if (err) {
      return res.status(500).send('Database connection failed.');
    }
    res.send('Database connection successful.');
  });
});

app.listen(5000, () => {
  console.log('Server started on port 5000');
});
