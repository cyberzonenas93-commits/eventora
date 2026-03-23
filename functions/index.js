const logger = require("./logger");

// ---------------------------------------------------------------------------
// Startup environment validation
// Warn loudly (non-fatal) about missing optional config so cold-start logs
// make misconfiguration immediately obvious in Cloud Console.
// ---------------------------------------------------------------------------
(function validateStartupEnv() {
  const warnings = [];

  const hubtelSmsId = process.env.HUBTEL_SMS_CLIENT_ID;
  const hubtelSmsSec = process.env.HUBTEL_SMS_CLIENT_SECRET;
  if (!hubtelSmsId || !hubtelSmsSec) {
    warnings.push(
      "HUBTEL_SMS_CLIENT_ID / HUBTEL_SMS_CLIENT_SECRET not set — SMS will fall back to Firestore app_config/hubtel.",
    );
  }

  const hubtelMerchant = process.env.HUBTEL_MERCHANT_ACCOUNT_NUMBER;
  const hubtelApiId = process.env.HUBTEL_API_CLIENT_ID;
  const hubtelApiSec = process.env.HUBTEL_API_CLIENT_SECRET;
  if (!hubtelMerchant || !hubtelApiId || !hubtelApiSec) {
    warnings.push(
      "HUBTEL_MERCHANT_ACCOUNT_NUMBER / HUBTEL_API_CLIENT_ID / HUBTEL_API_CLIENT_SECRET not set — payment checkout will fall back to Firestore app_config/hubtel.",
    );
  }

  const studioUrl = process.env.VENNUZO_STUDIO_URL;
  if (!studioUrl) {
    warnings.push(
      "VENNUZO_STUDIO_URL not set — payment redirect URLs will use the default fallback.",
    );
  }

  for (const warning of warnings) {
    logger.warn(`[startup] ${warning}`);
  }
})();

// ---------------------------------------------------------------------------

const adminSettings = require("./admin_settings");
const notifications = require("./event_notifications");
const organizerApplications = require("./organizer_applications");
const payments = require("./event_payments");
const placesLookup = require("./places_lookup");
const shareLinks = require("./share_link");

Object.assign(exports, adminSettings);
Object.assign(exports, notifications);
Object.assign(exports, organizerApplications);
Object.assign(exports, payments);
Object.assign(exports, placesLookup);
Object.assign(exports, shareLinks);
