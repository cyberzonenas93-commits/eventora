"use strict";

/**
 * Firestore rules-unit tests for admin role-based write gates on the moderation
 * and support queues. Proves a signed-in admin whose role lacks write
 * permission can no longer bypass the console by writing event_reports /
 * support_tickets directly. Run via `npm run test:rules`.
 */

const fs = require("fs");
const path = require("path");
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");
const { setDoc, updateDoc, doc, setLogLevel } = require("firebase/firestore");

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

async function seedAdmin(uid, role) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const data = { status: "active" };
    if (role) data.role = role;
    await setDoc(doc(ctx.firestore(), "admins", uid), data);
  });
}

async function seedReport(id) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "event_reports", id), {
      eventId: "e1",
      eventTitle: "Test Event",
      reason: "spam",
      details: "something that violates the rules here",
      status: "open",
      createdAt: new Date("2026-01-01T00:00:00Z"),
    });
  });
}

async function seedTicket(id) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "support_tickets", id), {
      userId: "some_user",
      status: "open",
    });
  });
}

function db(uid) {
  return testEnv.authenticatedContext(uid).firestore();
}

describe("event_reports moderation is gated by admin role", () => {
  test("trust_safety admin CAN set review status", async () => {
    await seedAdmin("admin_ts", "trust_safety");
    await seedReport("r1");
    await assertSucceeds(
      updateDoc(doc(db("admin_ts"), "event_reports", "r1"), {
        status: "reviewing",
        updatedAt: new Date("2026-01-02T00:00:00Z"),
      }),
    );
  });

  test("marketing_manager admin CANNOT moderate reports", async () => {
    await seedAdmin("admin_mk", "marketing_manager");
    await seedReport("r2");
    await assertFails(
      updateDoc(doc(db("admin_mk"), "event_reports", "r2"), {
        status: "resolved",
        updatedAt: new Date("2026-01-02T00:00:00Z"),
      }),
    );
  });

  test("an admin with no role CANNOT moderate reports", async () => {
    await seedAdmin("admin_nr", null);
    await seedReport("r3");
    await assertFails(
      updateDoc(doc(db("admin_nr"), "event_reports", "r3"), {
        status: "dismissed",
        updatedAt: new Date("2026-01-02T00:00:00Z"),
      }),
    );
  });
});

describe("support_tickets management is gated by admin role", () => {
  test("customer_support admin CAN update a ticket", async () => {
    await seedAdmin("admin_cs", "customer_support");
    await seedTicket("t1");
    await assertSucceeds(
      updateDoc(doc(db("admin_cs"), "support_tickets", "t1"), {
        status: "closed",
      }),
    );
  });

  test("read_only admin CANNOT update a ticket", async () => {
    await seedAdmin("admin_ro", "read_only");
    await seedTicket("t2");
    await assertFails(
      updateDoc(doc(db("admin_ro"), "support_tickets", "t2"), {
        status: "closed",
      }),
    );
  });
});
