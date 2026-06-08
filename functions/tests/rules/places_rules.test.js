"use strict";

/**
 * Firestore rules-unit tests for the Places trust boundary.
 * Proves the Phase 1 security fix at runtime: a client (even a place "manager")
 * cannot write the places collection or the OTP store; verified/featured are
 * therefore server-only. Requires the Firestore emulator — run via
 * `npm run test:rules`.
 */

const fs = require("fs");
const path = require("path");
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");
const { setDoc, getDoc, updateDoc, doc, setLogLevel } = require("firebase/firestore");

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

const UID = "owner_uid_1";

// A signed-in user who "owns" org_<uid> — i.e. a place manager under the rules.
function managerDb() {
  return testEnv.authenticatedContext(UID).firestore();
}

describe("places collection is server-only (verified/featured cannot be self-set)", () => {
  test("a manager CANNOT create a place (even for their own org)", async () => {
    const db = managerDb();
    await assertFails(
      setDoc(doc(db, "places", "gpl_test"), {
        organizationId: `org_${UID}`,
        name: "My Venue",
        status: "active",
        verified: true,
        verificationStatus: "verified",
        featured: true,
      }),
    );
  });

  test("a manager CANNOT update a place to self-set verified/featured", async () => {
    // Seed an unverified place owned by the manager's org, bypassing rules.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "places", "gpl_seed"), {
        organizationId: `org_${UID}`,
        name: "Seeded Venue",
        status: "active",
        verified: false,
        verificationStatus: "unverified",
        featured: false,
      });
    });
    const db = managerDb();
    await assertFails(
      updateDoc(doc(db, "places", "gpl_seed"), {
        verified: true,
        verificationStatus: "verified",
        featured: true,
      }),
    );
  });
});

describe("place_verification_otps is fully server-only", () => {
  test("a signed-in user CANNOT read an OTP doc", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "place_verification_otps", "gpl_seed_phone"), {
        codeHash: "x",
        salt: "y",
      });
    });
    const db = managerDb();
    await assertFails(getDoc(doc(db, "place_verification_otps", "gpl_seed_phone")));
  });

  test("a signed-in user CANNOT write an OTP doc", async () => {
    const db = managerDb();
    await assertFails(
      setDoc(doc(db, "place_verification_otps", "gpl_seed_phone"), { codeHash: "z" }),
    );
  });
});

describe("public read of active places still works", () => {
  test("anyone signed in CAN read an active place", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "places", "gpl_public"), {
        organizationId: "org_other",
        name: "Public Venue",
        status: "active",
      });
    });
    const db = managerDb();
    await assertSucceeds(getDoc(doc(db, "places", "gpl_public")));
  });

  test("a non-manager CANNOT read a non-active place", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "places", "gpl_hidden"), {
        organizationId: "org_other",
        name: "Hidden Venue",
        status: "hidden",
      });
    });
    const db = managerDb();
    await assertFails(getDoc(doc(db, "places", "gpl_hidden")));
  });
});
