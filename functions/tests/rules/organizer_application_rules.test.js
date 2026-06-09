"use strict";

/**
 * Firestore rules-unit tests for the organizer-application trust boundary.
 *
 * Proves the privilege-escalation fix: a client cannot author an
 * organizer_application that claims another org's id, so ownsOrganizerApplication
 * (and therefore isEventManager) can never grant a user event-manager rights
 * over a victim organization. Requires the Firestore emulator — run via
 * `npm run test:rules`.
 */

const fs = require("fs");
const path = require("path");
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");
const { setDoc, doc, setLogLevel } = require("firebase/firestore");

let testEnv;

beforeAll(async () => {
  setLogLevel("error");
  const hostPort = (process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080").split(":");
  testEnv = await initializeTestEnvironment({
    projectId: "vennuzo-rules-test",
    firestore: {
      rules: fs.readFileSync(path.resolve(__dirname, "../../../firestore.rules"), "utf8"),
      host: hostPort[0],
      port: Number(hostPort[1]),
    },
  });
});

afterAll(async () => {
  if (testEnv) await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

const ATTACKER = "attacker_uid";

function attackerDb() {
  return testEnv.authenticatedContext(ATTACKER).firestore();
}

describe("organizer_applications cannot claim another org (privilege escalation)", () => {
  test("CANNOT create an application claiming a victim org id", async () => {
    const db = attackerDb();
    await assertFails(
      setDoc(doc(db, "organizer_applications", ATTACKER), {
        userId: ATTACKER,
        status: "submitted",
        organizationId: "org_victim_uid",
      }),
    );
  });

  test("CAN create an application for the caller's own org id", async () => {
    const db = attackerDb();
    await assertSucceeds(
      setDoc(doc(db, "organizer_applications", ATTACKER), {
        userId: ATTACKER,
        status: "submitted",
        organizationId: `org_${ATTACKER}`,
      }),
    );
  });

  test("CAN still create an application with no organizationId yet", async () => {
    const db = attackerDb();
    await assertSucceeds(
      setDoc(doc(db, "organizer_applications", ATTACKER), {
        userId: ATTACKER,
        status: "draft",
      }),
    );
  });

  test("CANNOT create an application under another user's id", async () => {
    const db = attackerDb();
    await assertFails(
      setDoc(doc(db, "organizer_applications", "victim_uid"), {
        userId: "victim_uid",
        status: "submitted",
        organizationId: "org_victim_uid",
      }),
    );
  });
});
