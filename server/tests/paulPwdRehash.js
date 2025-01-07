const bcrypt = require('bcrypt');
const mysql = require('mysql2/promise');
const dotenv = require('dotenv');
const codeName = `[rehashMyPassword.js] `;

dotenv.config();

const rehashMyPassword = async () => {
  try {
    const userEmail = 'pc7900@gmail.com'; // Your email
    const plaintextPassword = 'Nothing123'; // Your plaintext password

    // Establish a connection to the database
    const connection = await mysql.createConnection({
      host: process.env.DB_HOST,
      user: process.env.DB_USER,
      password: process.env.DB_PASSWORD,
      database: process.env.DB_NAME
    });

    // Generate a new hash for the plaintext password
    const newHash = await bcrypt.hash(plaintextPassword, 10);
    console.log(`${codeName} New hashed password:`, newHash);

    // Update the database with the new hash
    const updateQuery = `UPDATE users SET password = '${newHash}' WHERE email = '${userEmail}'`;
    await connection.query(updateQuery);
    console.log(`${codeName} Password rehashed and updated for email:`, userEmail);

    // Close the connection
    await connection.end();
    console.log(`${codeName} Connection closed`);
  } catch (error) {
    console.error(`${codeName} Error rehashing password:`, error);
  }
};

// Run the rehashing process
rehashMyPassword();
