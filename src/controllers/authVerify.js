import bcrypt from 'bcrypt';

async function verifyPassword(req, res) {
  const { password, hashed_password } = req.body;

  if (!password || !hashed_password) {
    return res.status(400).json({ passwordMatches: false, error: 'Missing fields' });
  }

  const matches = await bcrypt.compare(password, hashed_password);
  return res.json({ passwordMatches: matches });
}

export default verifyPassword;
