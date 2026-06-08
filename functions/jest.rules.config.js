"use strict";

// Separate jest config for Firestore rules-unit tests. These require the
// Firestore emulator (run via `npm run test:rules`, which wraps this in
// `firebase emulators:exec`). The default unit-test run ignores tests/rules/.
module.exports = {
  testEnvironment: "node",
  testMatch: ["**/tests/rules/**/*.test.js"],
};
