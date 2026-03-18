const fs = require("fs");
const path = require("path");

function readLocalEnvFile() {
  const envPath = path.join(__dirname, ".env.local");
  if (!fs.existsSync(envPath)) {
    return {};
  }

  const lines = fs.readFileSync(envPath, "utf8").split(/\r?\n/);
  const values = {};
  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) {
      continue;
    }
    const separatorIndex = line.indexOf("=");
    if (separatorIndex <= 0) {
      continue;
    }
    const key = line.slice(0, separatorIndex).trim();
    const value = line.slice(separatorIndex + 1).trim();
    if (key) {
      values[key] = value;
    }
  }
  return values;
}

const localEnv = readLocalEnvFile();

module.exports = {
  clientId: process.env.HUBTEL_SMS_CLIENT_ID || localEnv.HUBTEL_SMS_CLIENT_ID || "",
  clientSecret:
    process.env.HUBTEL_SMS_CLIENT_SECRET || localEnv.HUBTEL_SMS_CLIENT_SECRET || "",
  senderId: process.env.HUBTEL_SMS_SENDER_ID || localEnv.HUBTEL_SMS_SENDER_ID || "GPlus",
};
