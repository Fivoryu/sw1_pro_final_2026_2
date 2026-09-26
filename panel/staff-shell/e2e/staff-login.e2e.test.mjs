import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createHmac, randomBytes } from "node:crypto";
import { readFileSync } from "node:fs";
import { createServer } from "node:net";
import { setTimeout as delay } from "node:timers/promises";
import { createRequire } from "node:module";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const shellDirectory = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const repositoryRoot = resolve(shellDirectory, "../..");
const backendDirectory = resolve(repositoryRoot, "backend");
let webOrigin;
const postgresImage = "postgres:16-alpine";
const pythonExecutable =
  process.platform === "win32"
    ? resolve(repositoryRoot, ".venv", "Scripts", "python.exe")
    : resolve(repositoryRoot, ".venv", "bin", "python");
const runId = randomBytes(8).toString("hex");
const databaseName = `roomforge_staff_e2e_${runId}`;
const databaseUser = `rf_e2e_${runId}`;
const databasePassword = randomBytes(24).toString("base64url");
const containerName = `roomforge-staff-login-e2e-${runId}`;
const staffEmail = `staff-e2e-${runId}@example.test`;
const staffPassword = `E2e-${randomBytes(24).toString("base64url")}!`;
const totpSecret = encodeBase32(randomBytes(20));
const jwtSecret = randomBytes(32).toString("base64url");
const totpEncryptionKey = randomBytes(32)
  .toString("base64")
  .replaceAll("+", "-")
  .replaceAll("/", "_");
const activeChildren = new Set();
let ownedContainerReference = null;
let browser = null;

const require = createRequire(import.meta.url);
const vitePackageJsonPath = require.resolve("vite/package.json");
const vitePackage = JSON.parse(readFileSync(vitePackageJsonPath, "utf8"));
const viteCli = resolve(dirname(vitePackageJsonPath), vitePackage.bin.vite);

function encodeBase32(bytes) {
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  let buffer = 0;
  let bitCount = 0;
  let output = "";

  for (const byte of bytes) {
    buffer = (buffer << 8) | byte;
    bitCount += 8;
    while (bitCount >= 5) {
      bitCount -= 5;
      output += alphabet[(buffer >>> bitCount) & 31];
    }
    buffer &= (1 << bitCount) - 1;
  }

  if (bitCount > 0) output += alphabet[(buffer << (5 - bitCount)) & 31];
  return output;
}

function createTotp(secret, timestamp = Date.now()) {
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  let buffer = 0;
  let bitCount = 0;
  const keyBytes = [];

  for (const character of secret) {
    const value = alphabet.indexOf(character);
    assert.notEqual(value, -1, "The seeded TOTP secret must be valid base32.");
    buffer = (buffer << 5) | value;
    bitCount += 5;
    if (bitCount >= 8) {
      bitCount -= 8;
      keyBytes.push((buffer >>> bitCount) & 0xff);
      buffer &= (1 << bitCount) - 1;
    }
  }

  const counter = Buffer.alloc(8);
  counter.writeBigUInt64BE(BigInt(Math.floor(timestamp / 30_000)));
  const digest = createHmacSha1(Buffer.from(keyBytes), counter);
  const offset = digest[digest.length - 1] & 0x0f;
  const binary = digest.readUInt32BE(offset) & 0x7fffffff;
  return String(binary % 1_000_000).padStart(6, "0");
}

function createHmacSha1(key, message) {
  return createHmac("sha1", key).update(message).digest();
}

function startChild(command, args, { cwd, env }) {
  const child = spawn(command, args, {
    cwd,
    env,
    stdio: ["ignore", "pipe", "pipe"],
    windowsHide: true,
  });
  let resolveClosed;
  const closedPromise = new Promise((resolvePromise) => {
    resolveClosed = resolvePromise;
  });
  const record = {
    child,
    output: "",
    closed: false,
    closedPromise,
    exitCode: null,
    signal: null,
    startError: null,
    waiters: new Set(),
  };
  activeChildren.add(record);

  const collect = (chunk) => {
    record.output = `${record.output}${chunk.toString("utf8")}`.slice(-64_000);
    for (const waiter of [...record.waiters]) {
      if (waiter.matcher.test(record.output)) {
        record.waiters.delete(waiter);
        clearTimeout(waiter.timer);
        waiter.resolve();
      }
    }
  };

  child.stdout.on("data", collect);
  child.stderr.on("data", collect);
  child.once("error", (error) => {
    record.startError = error;
    for (const waiter of [...record.waiters]) {
      record.waiters.delete(waiter);
      clearTimeout(waiter.timer);
      waiter.reject(
        new Error(
          startupDiagnostic(record, waiter.description, waiter.timeoutMs, waiter.port),
        ),
      );
    }
  });
  child.once("close", (exitCode, signal) => {
    record.closed = true;
    resolveClosed();
    record.exitCode = exitCode;
    record.signal = signal;
    activeChildren.delete(record);
    for (const waiter of [...record.waiters]) {
      record.waiters.delete(waiter);
      clearTimeout(waiter.timer);
      waiter.reject(
        new Error(
          startupDiagnostic(record, waiter.description, waiter.timeoutMs, waiter.port),
        ),
      );
    }
  });
  return record;
}

function sanitizedStartupOutputTail(output) {
  const standardEncryptionKey = totpEncryptionKey.replaceAll("-", "+").replaceAll("_", "/");
  const sensitiveValues = [
    databasePassword,
    staffPassword,
    totpSecret,
    jwtSecret,
    totpEncryptionKey,
    standardEncryptionKey,
    encodeURIComponent(databasePassword),
    encodeURIComponent(staffPassword),
    encodeURIComponent(totpSecret),
    encodeURIComponent(jwtSecret),
    encodeURIComponent(totpEncryptionKey),
    encodeURIComponent(standardEncryptionKey),
  ].filter(Boolean);
  let sanitized = output
    .replace(/\u001b\[[0-?]*[ -/]*[@-~]/g, "")
    .replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, " ");

  for (const value of sensitiveValues) {
    sanitized = sanitized.split(value).join("[REDACTED]");
  }
  sanitized = sanitized
    .replace(/(\b(?:password|secret|token|authorization|api[_-]?key|key)\s*[:=]\s*)(?:"[^"]*"|'[^']*'|[^\s,;]+)/gi, "$1[REDACTED]")
    .replace(/\b[A-Za-z0-9+/_=-]{32,}\b/g, "[REDACTED]");
  const tail = sanitized.slice(-1_200).trim();
  return tail ? `\nCaptured startup output (sanitized, last ${tail.length} characters):\n${tail}` : "";
}

function startupDiagnostic(record, description, timeoutMs, port) {
  const endpoint = port ? ` at 127.0.0.1:${port}` : "";
  if (/EADDRINUSE|address already in use|port \d+ is already in use/i.test(record.output)) {
    return `${description} could not start${endpoint}: the port is already in use (EADDRINUSE).`;
  }
  if (record.startError) {
    const code = record.startError.code ? ` (${record.startError.code})` : "";
    return `${description} could not start${code}.`;
  }
  if (record.closed) {
    const exit = record.exitCode === null ? record.signal : `exit ${record.exitCode}`;
    return `${description} exited before becoming ready${exit ? ` (${exit})` : ""}${endpoint}.`;
  }
  return `${description} did not become ready${endpoint} within ${Math.ceil(timeoutMs / 1_000)} seconds.${sanitizedStartupOutputTail(record.output)}`;
}

async function waitForHttpReady(record, origin, description, timeoutMs = 30_000, port) {
  const deadline = Date.now() + timeoutMs;
  const childExit = record.closedPromise.then(() => ({ exited: true }));

  while (Date.now() < deadline) {
    if (record.closed || record.startError) {
      throw new Error(startupDiagnostic(record, description, timeoutMs, port));
    }

    const probe = fetch(origin, {
      redirect: "manual",
      signal: AbortSignal.timeout(Math.min(1_000, deadline - Date.now())),
    })
      .then(async (response) => {
        const status = response.status;
        await response.body?.cancel();
        return { status };
      })
      .catch(() => ({ status: null }));
    const result = await Promise.race([probe, childExit]);
    if ("exited" in result) {
      throw new Error(startupDiagnostic(record, description, timeoutMs, port));
    }
    if (result.status === 200) return;
    await Promise.race([delay(250), childExit]);
  }

  throw new Error(startupDiagnostic(record, description, timeoutMs, port));
}

function waitForOutput(record, matcher, description, timeoutMs = 30_000, port) {
  if (matcher.test(record.output)) return Promise.resolve();
  if (record.closed || record.startError) {
    return Promise.reject(new Error(startupDiagnostic(record, description, timeoutMs, port)));
  }

  return new Promise((resolvePromise, rejectPromise) => {
    const waiter = {
      matcher,
      description,
      timeoutMs,
      port,
      resolve: resolvePromise,
      reject: rejectPromise,
      timer: setTimeout(() => {
        record.waiters.delete(waiter);
        rejectPromise(new Error(startupDiagnostic(record, description, timeoutMs, port)));
      }, timeoutMs),
    };
    record.waiters.add(waiter);
  });
}

function runCommand(command, args, { cwd, env, allowFailure = false }) {
  return new Promise((resolvePromise, rejectPromise) => {
    const child = spawn(command, args, {
      cwd,
      env,
      stdio: ["ignore", "pipe", "pipe"],
      windowsHide: true,
    });
    let resolveClosed;
    const closedPromise = new Promise((resolvePromise) => {
      resolveClosed = resolvePromise;
    });
    const record = { child, closed: false, closedPromise };
    activeChildren.add(record);
    let stdout = "";

    child.stdout.on("data", (chunk) => {
      stdout = `${stdout}${chunk.toString("utf8")}`.slice(-32_000);
    });
    child.stderr.on("data", () => {});
    child.once("error", () => {
      activeChildren.delete(record);
      rejectPromise(new Error("A required command could not start."));
    });
    child.once("close", (exitCode, signal) => {
      record.closed = true;
      resolveClosed();
      activeChildren.delete(record);
      if (exitCode === 0 || allowFailure) {
        resolvePromise({ exitCode, signal, stdout });
      } else {
        rejectPromise(new Error(`A required command failed (exit ${exitCode ?? signal}).`));
      }
    });
  });
}

function findFreeLoopbackPort() {
  return new Promise((resolvePromise, rejectPromise) => {
    const server = createServer();
    server.once("error", rejectPromise);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      if (!address || typeof address === "string") {
        server.close(() => rejectPromise(new Error("Could not reserve a local port.")));
        return;
      }
      server.close((error) => {
        if (error) rejectPromise(new Error("Could not release the temporary port reservation."));
        else resolvePromise(address.port);
      });
    });
  });
}

async function waitForPostgres(containerReference, user) {
  const deadline = Date.now() + 90_000;
  while (Date.now() < deadline) {
    const result = await runCommand(
      "docker",
      ["exec", containerReference, "pg_isready", "-q", "-U", user, "-d", databaseName],
      { cwd: repositoryRoot, env: process.env, allowFailure: true },
    );
    if (result.exitCode === 0) return;
    await delay(500);
  }
  throw new Error("The isolated PostgreSQL instance did not become ready in time.");
}

async function assertVisible(locator, message) {
  try {
    await locator.waitFor({ state: "visible", timeout: 20_000 });
  } catch {
    assert.fail(message);
  }
}

function waitForApiResponse(page, pathname, method) {
  return page.waitForResponse(
    (response) => {
      const url = new URL(response.url());
      return (
        url.origin === webOrigin &&
        url.pathname === pathname &&
        response.request().method() === method
      );
    },
    { timeout: 20_000 },
  );
}

async function runBrowserFlow() {
  browser = await chromium.launch({ headless: true });
  const context = await browser.newContext();
  const page = await context.newPage();
  const observedApiRequests = [];

  page.on("request", (request) => {
    const url = new URL(request.url());
    if (url.origin === webOrigin && url.pathname.startsWith("/api/")) {
      observedApiRequests.push(`${request.method()} ${url.pathname}`);
    }
  });

  await page.goto(webOrigin, { waitUntil: "domcontentloaded", timeout: 30_000 });
  await assertVisible(
    page.getByRole("heading", { level: 1, name: "Acceso de personal" }),
    "The staff login screen should be visible before authentication.",
  );

  const unauthenticatedMeStatus = await page.evaluate(async () => {
    const response = await fetch("/api/v1/auth/me");
    return response.status;
  });
  assert.equal(unauthenticatedMeStatus, 401, "Unauthenticated /me requests must be rejected.");

  await page.getByLabel("Correo electrónico").fill(staffEmail);
  await page.getByLabel("Contraseña", { exact: true }).fill(staffPassword);
  await page.getByRole("button", { name: "Continuar" }).click();
  await assertVisible(
    page.getByRole("heading", { level: 1, name: "Verificación en dos pasos" }),
    "Valid staff credentials should advance to the TOTP challenge.",
  );

  await page.getByLabel("Código de autenticación").fill(createTotp(totpSecret));
  const loginResponsePromise = waitForApiResponse(page, "/api/v1/auth/login/totp", "POST");
  await page.getByRole("button", { name: "Verificar acceso" }).click();
  const loginResponse = await loginResponsePromise;
  assert.equal(loginResponse.status(), 200, "A valid TOTP proof should authenticate the seeded staff account.");
  const loginPayload = await loginResponse.json();
  assert.equal(loginPayload.user.email, staffEmail, "The server should return the seeded account identity.");
  assert.equal(loginPayload.user.role, "platform_admin", "The server should resolve the staff role.");
  assert.equal(typeof loginPayload.access_token, "string", "Login should return an in-memory access token.");
  assert.equal(typeof loginPayload.csrf_token, "string", "Login should return the CSRF token.");

  await assertVisible(
    page.getByRole("heading", { level: 1, name: "Administración de plataforma" }),
    "A successful login should display the protected staff view.",
  );
  assert.equal(await page.getByText(staffEmail).isVisible(), true, "The protected view should show the authenticated identity.");

  const initialStorage = await page.evaluate(() => ({
    localStorageKeys: Object.keys(localStorage),
    sessionStorageKeys: Object.keys(sessionStorage),
    csrfToken: sessionStorage.getItem("roomforge.staff.csrf"),
  }));
  assert.deepEqual(initialStorage.localStorageKeys, [], "Authentication tokens must not be stored in localStorage.");
  assert.deepEqual(initialStorage.sessionStorageKeys, ["roomforge.staff.csrf"], "Only the tab-scoped CSRF token may persist.");
  assert.ok(initialStorage.csrfToken, "The browser should retain the CSRF token for session restoration.");

  const authCookies = await context.cookies(`${webOrigin}/api/v1/auth`);
  const refreshCookie = authCookies.find((cookie) => cookie.name === "roomforge_refresh");
  assert.ok(refreshCookie, "Login should set the refresh cookie.");
  const initialRefreshCookieValue = refreshCookie.value;
  assert.equal(refreshCookie.httpOnly, true, "The refresh cookie must be HttpOnly.");
  assert.equal(refreshCookie.secure, false, "The local HTTP test cookie must not require TLS.");
  assert.equal(refreshCookie.path, "/api/v1/auth", "The refresh cookie should remain scoped to auth endpoints.");

  const invalidCsrfStatus = await page.evaluate(async () => {
    const response = await fetch("/api/v1/auth/refresh", {
      method: "POST",
      headers: { "X-CSRF-Token": "invalid-staff-login-e2e-csrf" },
    });
    return response.status;
  });
  assert.equal(invalidCsrfStatus, 403, "A refresh request with an invalid CSRF token must be rejected.");

  const refreshResponsePromise = waitForApiResponse(page, "/api/v1/auth/refresh", "POST");
  const restoredMePromise = waitForApiResponse(page, "/api/v1/auth/me", "GET");
  await page.reload({ waitUntil: "domcontentloaded" });
  const refreshResponse = await refreshResponsePromise;
  assert.equal(refreshResponse.status(), 200, "Reload should restore the session by rotating refresh and CSRF tokens.");
  const refreshPayload = await refreshResponse.json();
  const restoredMeResponse = await restoredMePromise;
  assert.equal(restoredMeResponse.status(), 200, "Reload should resolve the protected identity through /me.");
  await assertVisible(
    page.getByRole("heading", { level: 1, name: "Administración de plataforma" }),
    "The protected staff view should be restored after a page reload.",
  );
  const restoredStorage = await page.evaluate(() => ({
    csrfToken: sessionStorage.getItem("roomforge.staff.csrf"),
    localStorageKeys: Object.keys(localStorage),
  }));
  assert.notEqual(restoredStorage.csrfToken, initialStorage.csrfToken, "Session restoration should persist the rotated CSRF token.");
  assert.equal(restoredStorage.csrfToken, refreshPayload.csrf_token, "The rotated CSRF token should match the refresh response.");
  const rotatedCookie = (await context.cookies(`${webOrigin}/api/v1/auth`)).find(
    (cookie) => cookie.name === "roomforge_refresh",
  );
  assert.ok(rotatedCookie, "Session restoration should retain a refresh cookie.");
  assert.notEqual(rotatedCookie.value, initialRefreshCookieValue, "Session restoration should rotate the HttpOnly refresh cookie.");
  assert.deepEqual(restoredStorage.localStorageKeys, [], "Reload must not persist access or refresh tokens in localStorage.");

  const logoutResponsePromise = waitForApiResponse(page, "/api/v1/auth/logout", "POST");
  await page.getByRole("button", { name: "Cerrar sesión" }).click();
  const logoutResponse = await logoutResponsePromise;
  assert.equal(logoutResponse.status(), 204, "Logout should revoke the server-side session.");
  await assertVisible(
    page.getByRole("heading", { level: 1, name: "Acceso de personal" }),
    "Logout should return the browser to the staff login screen.",
  );
  assert.equal(
    await page.evaluate(() => sessionStorage.getItem("roomforge.staff.csrf")),
    null,
    "Logout should clear the tab-scoped CSRF token.",
  );
  assert.equal(
    (await context.cookies(`${webOrigin}/api/v1/auth`)).some((cookie) => cookie.name === "roomforge_refresh"),
    false,
    "Logout should clear the HttpOnly refresh cookie.",
  );

  const revokedMeStatus = await page.evaluate(async (accessToken) => {
    const response = await fetch("/api/v1/auth/me", {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    return response.status;
  }, loginPayload.access_token);
  assert.equal(revokedMeStatus, 401, "The pre-logout access token must fail after its session is revoked.");

  for (const endpoint of [
    "POST /api/v1/auth/login",
    "POST /api/v1/auth/login/totp",
    "GET /api/v1/auth/me",
    "POST /api/v1/auth/refresh",
    "POST /api/v1/auth/logout",
  ]) {
    assert.ok(observedApiRequests.includes(endpoint), `${endpoint} should be sent by the browser through Vite's /api proxy.`);
  }

  await context.close();
  await browser.close();
  browser = null;
}

async function createIsolatedPostgres() {
  const databasePasswordEncoded = encodeURIComponent(databasePassword);
  const containerResult = await runCommand(
    "docker",
    [
      "run",
      "--detach",
      "--rm",
      "--name",
      containerName,
      "--label",
      `roomforge.staff-login-e2e.run=${runId}`,
      "--publish",
      "127.0.0.1::5432",
      "--tmpfs",
      "/var/lib/postgresql/data:rw,noexec,nosuid,size=536870912",
      "--env",
      `POSTGRES_DB=${databaseName}`,
      "--env",
      `POSTGRES_USER=${databaseUser}`,
      "--env",
      `POSTGRES_PASSWORD=${databasePassword}`,
      postgresImage,
    ],
    { cwd: repositoryRoot, env: process.env },
  );
  ownedContainerReference = containerResult.stdout.trim().split(/\s+/)[0] || containerName;

  const portResult = await runCommand(
    "docker",
    ["port", ownedContainerReference, "5432/tcp"],
    { cwd: repositoryRoot, env: process.env },
  );
  const portMatch = portResult.stdout.match(/^127\.0\.0\.1:(\d+)\s*$/m);
  assert.ok(portMatch, "The isolated PostgreSQL port must be published only on loopback.");
  const postgresPort = Number(portMatch[1]);
  assert.ok(postgresPort > 0 && postgresPort <= 65_535, "Docker should assign a random host port.");

  await waitForPostgres(ownedContainerReference, databaseUser);
  return `postgresql+psycopg://${encodeURIComponent(databaseUser)}:${databasePasswordEncoded}@127.0.0.1:${postgresPort}/${databaseName}`;
}

async function cleanup() {
  if (browser) {
    try {
      await browser.close();
    } catch {
      // Continue stopping only resources created by this runner.
    }
    browser = null;
  }

  const childRecords = [...activeChildren];
  for (const record of childRecords) {
    if (!record.closed) record.child.kill("SIGTERM");
  }
  await Promise.all(
    childRecords.map(async (record) => {
      if (record.closed) return;
      await Promise.race([record.closedPromise, delay(5_000)]);
      if (!record.closed) record.child.kill(process.platform === "win32" ? undefined : "SIGKILL");
    }),
  );

  if (ownedContainerReference) {
    try {
      await runCommand("docker", ["stop", ownedContainerReference], {
        cwd: repositoryRoot,
        env: process.env,
        allowFailure: true,
      });
    } catch {
      // The --rm container may already have exited; never remove any volumes or other resources.
    }
    ownedContainerReference = null;
  }
}

async function main() {
  let statusMessage = null;
  try {
    const backendPort = await findFreeLoopbackPort();
    let vitePort = await findFreeLoopbackPort();
    while (vitePort === backendPort) vitePort = await findFreeLoopbackPort();
    webOrigin = `http://127.0.0.1:${vitePort}`;
    const backendOrigin = `http://127.0.0.1:${backendPort}`;
    const vite = startChild(
      process.execPath,
      [viteCli, "--host", "127.0.0.1", "--port", String(vitePort), "--strictPort"],
      { cwd: shellDirectory, env: { ...process.env, VITE_API_TARGET: backendOrigin } },
    );
    await waitForHttpReady(vite, webOrigin, "Vite", 30_000, vitePort);

    const databaseUrl = await createIsolatedPostgres();
    const backendEnv = {
      ...process.env,
      DATABASE_URL: databaseUrl,
      JWT_SECRET: jwtSecret,
      STAFF_TOTP_ENCRYPTION_KEY: totpEncryptionKey,
      STAFF_WEB_ORIGIN: webOrigin,
      STAFF_SECURE_COOKIES: "false",
      PYTHONDONTWRITEBYTECODE: "1",
      PYTHONUNBUFFERED: "1",
      STAFF_LOGIN_E2E_RUN_ID: runId,
      STAFF_LOGIN_E2E_EMAIL: staffEmail,
      STAFF_LOGIN_E2E_PASSWORD: staffPassword,
      STAFF_LOGIN_E2E_TOTP_SECRET: totpSecret,
    };

    await runCommand(pythonExecutable, ["-m", "alembic", "upgrade", "head"], {
      cwd: backendDirectory,
      env: backendEnv,
    });
    await runCommand(pythonExecutable, ["tests/staff_login_e2e_seed.py"], {
      cwd: backendDirectory,
      env: backendEnv,
    });

    const backend = startChild(
      pythonExecutable,
      [
        "-m",
        "uvicorn",
        "app.main:create_app",
        "--factory",
        "--host",
        "127.0.0.1",
        "--port",
        String(backendPort),
      ],
      { cwd: backendDirectory, env: backendEnv },
    );
    await waitForOutput(
      backend,
      /Uvicorn running on http:\/\/127\.0\.0\.1:\d+/i,
      "FastAPI",
      30_000,
      backendPort,
    );

    await runBrowserFlow();
    statusMessage = "Staff login browser E2E passed: login, TOTP, /me, reload/restore, logout/revocation, and auth/CSRF negatives.";
  } finally {
    await cleanup();
  }
  if (statusMessage) console.log(statusMessage);
}

try {
  await main();
} catch (error) {
  const message = error instanceof Error ? error.message : "Unexpected test failure.";
  console.error(`Staff login browser E2E failed: ${message}`);
  process.exitCode = 1;
}
