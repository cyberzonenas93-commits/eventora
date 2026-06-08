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

  const smtpUser = process.env.SMTP_USER;
  const smtpPass = process.env.SMTP_PASS;
  if (!smtpUser || !smtpPass) {
    warnings.push(
      "SMTP_USER / SMTP_PASS not set — ticket email delivery will fall back to Firestore app_config/email.",
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
const creativeServices = require("./creative_services");
const adminConsole = require("./admin_console");
const analytics = require("./analytics");
const supportChat = require("./support_chat");
const eventParity = require("./event_parity");
const eventSafety = require("./event_safety");
const eventOps = require("./event_ops");
const phoneAuth = require("./phone_auth");
const gplusSync = require("./gplus_sync");
const placesPlatform = require("./places_platform");
const gplusTicketBridge = require("./gplus_ticket_bridge");

Object.assign(exports, adminSettings);
Object.assign(exports, notifications);
Object.assign(exports, organizerApplications);
Object.assign(exports, payments);
Object.assign(exports, placesLookup);
Object.assign(exports, shareLinks);
Object.assign(exports, creativeServices);
Object.assign(exports, adminConsole);
Object.assign(exports, analytics);
Object.assign(exports, supportChat);
Object.assign(exports, eventParity);
Object.assign(exports, eventSafety);
Object.assign(exports, eventOps);
Object.assign(exports, phoneAuth);
Object.assign(exports, gplusSync);
Object.assign(exports, placesPlatform);
Object.assign(exports, gplusTicketBridge);
