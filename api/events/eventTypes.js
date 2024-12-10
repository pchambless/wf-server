const express = require('express');
const router = express.Router();
const db = require('../db');

router.get('/list', (req, res) => {
  const sql = `select * from v_apiEventsLoad`;

  db.query(sql, (err, results) => {
    if (err) {
      return res.status(500).send(err);
    }
    res.json(results);
  });
});

module.exports = router;
