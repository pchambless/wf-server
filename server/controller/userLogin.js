require('module-alias/register');
const bcrypt = require('bcrypt');
const db = require('@utils/dbUtils'); // Ensure this is your DB utility module

module.exports = async (req, res) => {
  const { userEmail, password } = req.body;

  try {
    const query = 'SELECT id, password FROM users WHERE email = ?';
    const [results] = await db.executeQuery(query, [userEmail]);

    if (results.length === 0) {
      return res.status(401).send('Unauthorized: Invalid email or password');
    }

    const user = results[0];
    const isPasswordValid = await bcrypt.compare(password, user.password);

    if (!isPasswordValid) {
      return res.status(401).send('Unauthorized: Invalid email or password');
    }

    res.status(200).json({ message: 'Login successful', userId: user.id });
  } catch (error) {
    console.error('Error processing login:', error);
    res.status(500).send('Internal server error');
  }
};
