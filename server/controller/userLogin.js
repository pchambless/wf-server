const bcrypt = require('bcrypt');
const { executeQuery } = require('@utils/dbUtils');
const codeName = `[userLogin] `;

const rehashPassword = async (userEmail, plaintextPassword) => {
  try {
    // Generate a new hash for the plaintext password
    const newHash = await bcrypt.hash(plaintextPassword, 10);
    console.log(`${codeName} New hashed password:`, newHash);

    // Update the database with the new hash
    const updateQuery = `UPDATE users SET password = '${newHash}' WHERE userEmail = '${userEmail}'`;
    await executeQuery(updateQuery, 'UPDATE');
    console.log(`${codeName} Password rehashed and updated for email:`, userEmail);
  } catch (error) {
    console.error(`${codeName} Error rehashing password:`, error);
  }
};

module.exports = async (req, res) => {
  try {
    console.log(`${codeName} Login attempt started`); 

    // Extract userEmail and password from the request body
    const { userEmail, password } = req.body;

    if (!userEmail || !password) {
      console.log(`${codeName} Missing email or password`);
      return res.status(400).send({ message: 'Email and password are required' });
    }

    // Construct the query to get the user by email
    const query = `SELECT userID, password, roleID, acctID, acctName, userEmail FROM v_userLogin WHERE userEmail = '${userEmail}'`;  
    console.log(`${codeName} Executing query: ${query}`);

    const results = await executeQuery(query, 'GET');

    if (results.length === 0) {
      console.log(`${codeName} Email not found`);
      return res.status(401).send({ message: 'Unauthorized' });
    }

    const user = results[0];
    const storedPassword = user.password;

    // Adjust prefix if needed
    const adjustedStoredPassword = storedPassword.replace('$2y$', '$2b$');

    // Use bcrypt to compare the provided password with the stored hashed password
    const passwordMatch = await bcrypt.compare(password, adjustedStoredPassword);
    console.log(`${codeName} Password match:`, passwordMatch);

    if (!passwordMatch) {
      console.log(`${codeName} Invalid password`);
      return res.status(401).send({ message: 'Unauthorized' });
    }

    // Check if the password needs to be rehashed
    const needsRehash = adjustedStoredPassword.startsWith('$2b$') && adjustedStoredPassword.length !== 60;
    if (needsRehash) {
      await rehashPassword(userEmail, password);
    }

    const response = { success: true, data: { user } };
    console.log(`${codeName} Sending response:`, response);
    res.status(200).send(response);
  } catch (error) {
    console.error(`${codeName} Error processing login:`, error);
    res.status(500).send({ message: 'Internal Server Error' });
  }
};
