const notifications = require("./event_notifications");
const organizerApplications = require("./organizer_applications");
const payments = require("./event_payments");

Object.assign(exports, notifications);
Object.assign(exports, organizerApplications);
Object.assign(exports, payments);
