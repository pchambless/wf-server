const bcrypt = require('bcrypt');

const testPassword = async () => {
  const providedPassword = 'Nothing123'; // User-provided password
  let storedHash = '$2y$10$1tiM6W/yTf/gqaCiH4QHWeHb1nkQBhpGlEie3iBrELyze5qebx/YC'; // Stored hashed password

  // Convert $2y$ to $2b$
  storedHash = storedHash.replace('$2y$', '$2b$');

  console.log(`Provided password:`, providedPassword);
  console.log(`Converted stored hashed password:`, storedHash);

  // Perform the comparison
  const passwordMatch = await bcrypt.compare(providedPassword, storedHash);
  console.log(`Password match:`, passwordMatch);
};

// Run the test
testPassword();


const verifyPassword = async () => {
  const providedPassword = 'Nothing123';
  const knownHash = await bcrypt.hash(providedPassword, 10);

  console.log(`Known hash:`, knownHash);

  // Compare the known hash
  const passwordMatch = await bcrypt.compare(providedPassword, knownHash);
  console.log(`Password match with known hash:`, passwordMatch);
};

const consistencyCheck = async () => {
  const password = 'Nothing123';
  const knownHash = '$2y$10$1tiM6W/yTf/gqaCiH4QHWeHb1nkQBhpGlEie3iBrELyze5qebx/YC';

  // Check consistency
  const isMatch = await bcrypt.compare(password, knownHash);
  console.log(`Consistency check result:`, isMatch); // Should be true
};

// Run the tests
testPassword();
verifyPassword();
consistencyCheck();
