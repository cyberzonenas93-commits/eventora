"use strict";

/**
 * Structured logger for Vennuzo Cloud Functions.
 *
 * Outputs JSON log entries that Google Cloud Logging parses automatically
 * into severity, message, and structured fields — enabling log-based metrics,
 * alerting, and filtering in Cloud Console.
 *
 * Usage:
 *   const logger = require("./logger");
 *   logger.info("Order created", { orderId, uid });
 *   logger.error("Hubtel callback failed", new Error("timeout"));
 */

function buildEntry(severity, message, context) {
  const entry = {
    severity,
    message,
    time: new Date().toISOString(),
  };

  if (context instanceof Error) {
    entry.errorMessage = context.message;
    entry.stack = context.stack;
    if (context.code) entry.code = context.code;
  } else if (context && typeof context === "object" && !Array.isArray(context)) {
    for (const [key, value] of Object.entries(context)) {
      if (["severity", "message", "time"].includes(key)) continue;
      entry[key] = value;
    }
  } else if (context !== undefined) {
    entry.data = context;
  }

  return entry;
}

const logger = {
  debug(message, context) {
    if (process.env.FUNCTIONS_DEBUG === "true") {
      console.log(JSON.stringify(buildEntry("DEBUG", message, context)));
    }
  },
  info(message, context) {
    console.log(JSON.stringify(buildEntry("INFO", message, context)));
  },
  warn(message, context) {
    console.warn(JSON.stringify(buildEntry("WARNING", message, context)));
  },
  error(message, context) {
    console.error(JSON.stringify(buildEntry("ERROR", message, context)));
  },
  critical(message, context) {
    console.error(JSON.stringify(buildEntry("CRITICAL", message, context)));
  },
};

module.exports = logger;
