"use strict";

const logger = require("../logger");

describe("logger", () => {
  let logSpy, warnSpy, errorSpy;

  beforeEach(() => {
    logSpy = jest.spyOn(console, "log").mockImplementation(() => {});
    warnSpy = jest.spyOn(console, "warn").mockImplementation(() => {});
    errorSpy = jest.spyOn(console, "error").mockImplementation(() => {});
  });

  afterEach(() => {
    jest.restoreAllMocks();
    delete process.env.FUNCTIONS_DEBUG;
  });

  test("info() emits valid JSON with severity=INFO", () => {
    logger.info("test message", { orderId: "abc123" });
    expect(logSpy).toHaveBeenCalledTimes(1);
    const parsed = JSON.parse(logSpy.mock.calls[0][0]);
    expect(parsed.severity).toBe("INFO");
    expect(parsed.message).toBe("test message");
    expect(parsed.orderId).toBe("abc123");
    expect(parsed.time).toBeDefined();
  });

  test("warn() emits severity=WARNING", () => {
    logger.warn("watch out");
    const parsed = JSON.parse(warnSpy.mock.calls[0][0]);
    expect(parsed.severity).toBe("WARNING");
  });

  test("error() with Error object extracts stack and message", () => {
    const err = new Error("something broke");
    logger.error("oops", err);
    const parsed = JSON.parse(errorSpy.mock.calls[0][0]);
    expect(parsed.severity).toBe("ERROR");
    expect(parsed.errorMessage).toBe("something broke");
    expect(parsed.stack).toContain("Error:");
  });

  test("critical() emits severity=CRITICAL", () => {
    logger.critical("fatal error");
    const parsed = JSON.parse(errorSpy.mock.calls[0][0]);
    expect(parsed.severity).toBe("CRITICAL");
  });

  test("debug() is silent unless FUNCTIONS_DEBUG=true", () => {
    logger.debug("hidden");
    expect(logSpy).not.toHaveBeenCalled();

    process.env.FUNCTIONS_DEBUG = "true";
    logger.debug("visible");
    expect(logSpy).toHaveBeenCalledTimes(1);
    const parsed = JSON.parse(logSpy.mock.calls[0][0]);
    expect(parsed.severity).toBe("DEBUG");
  });

  test("reserved fields are not overwritten by context", () => {
    logger.info("msg", { severity: "FAKE", message: "override", time: "bad" });
    const parsed = JSON.parse(logSpy.mock.calls[0][0]);
    expect(parsed.severity).toBe("INFO");
    expect(parsed.message).toBe("msg");
  });
});
