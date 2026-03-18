const notifications = require("./event_notifications");
const organizerApplications = require("./organizer_applications");
const payments = require("./event_payments");
const placesLookup = require("./places_lookup");
const shareLinks = require("./share_link");

Object.assign(exports, notifications);
Object.assign(exports, organizerApplications);
Object.assign(exports, payments);
Object.assign(exports, placesLookup);
Object.assign(exports, shareLinks);
