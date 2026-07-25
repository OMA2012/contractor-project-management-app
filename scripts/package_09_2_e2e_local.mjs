import { createClient } from "@supabase/supabase-js";
import { bootstrapProductionOwner } from "./bootstrap_production_owner.mjs";

export const EXIT = Object.freeze({
  ok: 0,
  validation: 1,
  supabase: 2,
  edgeStartup: 3,
  owner: 4,
  client: 5,
  invitationLifecycle: 6,
  lifecycle: 7,
  authorization: 8,
  cleanup: 9,
  internal: 10,
});

export const FUNCTION_NAMES = Object.freeze([
  "create-client-invitation",
  "resend-client-invitation",
  "revoke-client-invitation",
  "accept-client-invitation",
  "suspend-client-account",
  "reactivate-client-account",
  "disable-client-account",
]);

const APP_BASE_URL = "http://localhost:3000";
const CONFIRMATION = "CREATE FIRST CONTRACTOR OWNER";
const TEMP_ENV_NAME = "package_09_2_e2e_functions.env";
const TEST_DOMAIN = "example.test";

function e2eError(message, exitCode) {
  return Object.assign(new Error(message), { exitCode });
}

export function assertLocalSupabaseUrl(value) {
  const url = new URL(value);
  const local = url.protocol === "http:" &&
    (url.hostname === "127.0.0.1" || url.hostname === "localhost");
  if (!local) {
    throw e2eError(
      "SUPABASE_URL must point to local Supabase.",
      EXIT.validation,
    );
  }
  return url.toString().replace(/\/$/, "");
}

export function redact(value) {
  if (typeof value === "string") {
    return value
      .replaceAll(/Bearer\s+[A-Za-z0-9._-]+/g, "Bearer [REDACTED]")
      .replaceAll(
        /(token|token_hash|access_token|refresh_token)=([^&\s"']+)/gi,
        "$1=[REDACTED]",
      )
      .replaceAll(
        /https?:\/\/[^\s"'<>]*(?:token|token_hash|otp|code)[^\s"'<>]*/gi,
        "[REDACTED_URL]",
      )
      .replaceAll(/\beyJ[A-Za-z0-9._-]+/g, "[REDACTED_JWT]")
      .replaceAll(/\b[A-Za-z0-9_-]{32,}\b/g, "[REDACTED_VALUE]");
  }
  if (Array.isArray(value)) return value.map(redact);
  if (value && typeof value === "object") {
    const output = {};
    for (const [key, nested] of Object.entries(value)) {
      output[key] = /authorization|token|otp|password|secret|key/i.test(key)
        ? "[REDACTED]"
        : redact(nested);
    }
    return output;
  }
  return value;
}

export function safeLine(key, value = "ok") {
  return `${key}=${String(redact(value))}`;
}

export function parseSupabaseStatus(raw) {
  const start = raw.indexOf("{");
  if (start < 0) {
    throw e2eError("supabase status did not return JSON.", EXIT.supabase);
  }
  const status = JSON.parse(raw.slice(start));
  for (
    const key of [
      "API_URL",
      "MAILPIT_URL",
      "PUBLISHABLE_KEY",
      "SERVICE_ROLE_KEY",
    ]
  ) {
    if (typeof status[key] !== "string" || !status[key]) {
      throw e2eError(`supabase status is missing ${key}.`, EXIT.supabase);
    }
  }
  const apiUrl = assertLocalSupabaseUrl(status.API_URL);
  if (typeof status.FUNCTIONS_URL !== "string" || !status.FUNCTIONS_URL) {
    status.FUNCTIONS_URL = `${apiUrl}/functions/v1`;
  }
  return status;
}

export async function writeNoBomEnvFile(path, fs = Deno) {
  await fs.writeTextFile(path, `APP_BASE_URL=${APP_BASE_URL}\n`);
  const bytes = await fs.readFile(path);
  if (bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf) {
    throw e2eError(
      "temporary env file must not contain a BOM.",
      EXIT.validation,
    );
  }
}

export function extractInviteParts(message) {
  const body = String(
    [message.Text, message.HTML, message.Raw].filter(Boolean).join("\n"),
  )
    .replaceAll("&amp;", "&");
  const urls = body.match(/https?:\/\/[^\s"'<>]+/g) ?? [];
  const verifyUrl = urls.map((item) => {
    try {
      return new URL(item);
    } catch {
      return null;
    }
  }).find((url) => url?.pathname.includes("/auth/v1/verify"));
  if (!verifyUrl) {
    throw e2eError("invitation verification URL was not found.", EXIT.internal);
  }
  const tokenHash = verifyUrl.searchParams.get("token");
  if (!tokenHash) {
    throw e2eError(
      "invitation verification token was not found.",
      EXIT.internal,
    );
  }
  const redirectRaw = verifyUrl.searchParams.get("redirect_to");
  const redirectUrl = redirectRaw ? new URL(redirectRaw) : null;
  return {
    tokenHash,
    appToken: redirectUrl?.searchParams.get("token") ?? null,
    safeVerifyRoute: `${verifyUrl.host}${verifyUrl.pathname}`,
    safeRedirectRoute: redirectUrl
      ? `${redirectUrl.host}${redirectUrl.pathname}`
      : "none",
  };
}

export async function waitForMail(
  { fetchImpl = fetch, mailpitUrl, email, sinceMs = 0, timeoutMs = 30000 },
) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const list = await fetchImpl(`${mailpitUrl}/api/v1/messages`);
    if (!list.ok) {
      throw e2eError("Mailpit message listing failed.", EXIT.internal);
    }
    const json = await list.json();
    const messages = Array.isArray(json.messages) ? json.messages : [];
    const candidate = messages.find((message) => {
      const recipients = JSON.stringify(message.To ?? message.to ?? [])
        .toLowerCase();
      const created = Date.parse(message.Created ?? message.created ?? "") || 0;
      return recipients.includes(email.toLowerCase()) &&
        created >= sinceMs - 2000;
    });
    if (candidate) {
      const id = candidate.ID ?? candidate.Id ?? candidate.id;
      const detail = await fetchImpl(`${mailpitUrl}/api/v1/message/${id}`);
      if (!detail.ok) {
        throw e2eError("Mailpit message read failed.", EXIT.internal);
      }
      return await detail.json();
    }
    await delay(500);
  }
  throw e2eError(
    `Timed out waiting for mail for ${maskEmail(email)}.`,
    EXIT.internal,
  );
}

export async function clearMailpit(fetchImpl, mailpitUrl) {
  await fetchImpl(`${mailpitUrl}/api/v1/messages`, { method: "DELETE" }).catch(
    () => undefined,
  );
}

export async function runCommand(name, args, options = {}) {
  const command = new Deno.Command(name, {
    args,
    cwd: options.cwd,
    stdout: "piped",
    stderr: "piped",
  });
  const output = await command.output();
  const stdout = new TextDecoder().decode(output.stdout);
  const stderr = new TextDecoder().decode(output.stderr);
  if (!output.success) {
    throw e2eError(
      `${name} ${args.join(" ")} failed: ${redact(stderr || stdout)}`,
      options.exitCode ?? EXIT.internal,
    );
  }
  return stdout;
}

export async function startFunctionsServe(
  { cwd, envFile, timeoutMs = 45000, commandFactory = Deno.Command },
) {
  const command = new commandFactory("supabase", {
    args: ["functions", "serve", "--env-file", envFile],
    cwd,
    stdout: "piped",
    stderr: "piped",
  });
  const child = command.spawn();
  const decoder = new TextDecoder();
  let output = "";
  const readers = [child.stdout, child.stderr].map(async (stream) => {
    for await (const chunk of stream) {
      output += decoder.decode(chunk);
    }
  });
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (
      FUNCTION_NAMES.every((name) => output.includes(name)) ||
      output.includes("... and 2 more functions")
    ) {
      return {
        child,
        output: () => redact(output),
        stop: async () => {
          child.kill("SIGTERM");
          await Promise.race([child.status, delay(3000)]).catch(() =>
            undefined
          );
          await Promise.allSettled(readers);
        },
      };
    }
    await delay(500);
  }
  child.kill("SIGTERM");
  await Promise.allSettled(readers);
  throw e2eError(
    `Edge Function startup timed out: ${redact(output)}`,
    EXIT.edgeStartup,
  );
}

export async function cleanupAll(
  { status, serve, envFile, root, reset = true, lines },
) {
  const failures = [];
  try {
    if (serve) await serve.stop();
  } catch (error) {
    failures.push(error);
  }
  try {
    if (envFile) await Deno.remove(envFile);
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) failures.push(error);
  }
  try {
    if (status?.MAILPIT_URL) await clearMailpit(fetch, status.MAILPIT_URL);
  } catch (error) {
    failures.push(error);
  }
  if (reset) {
    try {
      await runCommand("supabase", ["db", "reset", "--local"], {
        cwd: root,
        exitCode: EXIT.cleanup,
      });
    } catch (error) {
      failures.push(error);
    }
  }
  if (failures.length > 0) {
    lines?.push(safeLine("cleanup", "failed"));
    throw e2eError("Cleanup failed.", EXIT.cleanup);
  }
  lines?.push(safeLine("cleanup", "ok"));
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function maskEmail(email) {
  const [local, domain] = email.split("@");
  return `${local.slice(0, 2)}***@${domain}`;
}

function serviceClient(status) {
  return createClient(status.API_URL, status.SERVICE_ROLE_KEY, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  });
}

function publicClient(status, jwt) {
  return createClient(status.API_URL, status.PUBLISHABLE_KEY, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
    global: jwt ? { headers: { Authorization: `Bearer ${jwt}` } } : undefined,
  });
}

async function sql(query) {
  return (await runCommand("docker", [
    "exec",
    "supabase_db_contractor-project-management-app",
    "psql",
    "-U",
    "postgres",
    "-d",
    "postgres",
    "-At",
    "-c",
    query,
  ])).trim();
}

function q(value) {
  return String(value).replaceAll("'", "''");
}

async function tableStateByUserId(userId) {
  const result = await sql(`
select u.id::text || '|' || u.auth_subject::text || '|' || u.user_type || '|' || u.status || '|' || u.is_active::text || '|' ||
count(distinct p.user_id)::text || '|' ||
count(distinct ur.id) filter (where ur.is_active)::text || '|' ||
coalesce((select i.status from app.user_invitations i where i.invited_user_id = u.id order by i.created_at desc, i.id desc limit 1), '')
from app.users u
left join app.user_profiles p on p.user_id = u.id
left join app.user_roles ur on ur.user_id = u.id
where u.id = '${q(userId)}'::uuid
group by u.id`);
  if (!result) throw e2eError("expected app user row.", EXIT.internal);
  const [
    id,
    authSubject,
    userType,
    status,
    active,
    profileCount,
    activeRoleCount,
    invitationStatus,
  ] = result.split("|");
  return {
    id,
    authSubject,
    userType,
    status,
    isActive: active === "true",
    profileCount: Number(profileCount),
    activeRoleCount: Number(activeRoleCount),
    invitationStatus,
  };
}

async function userIdByAuthSubject(authSubject) {
  return await sql(
    `select id::text from app.users where auth_subject = '${
      q(authSubject)
    }'::uuid`,
  );
}

async function invitationCount(userId) {
  return Number(
    await sql(
      `select count(*)::int from app.user_invitations where invited_user_id = '${
        q(userId)
      }'::uuid`,
    ),
  );
}

async function authBanState(authSubject, admin) {
  const { data, error } = await admin.auth.admin.getUserById(authSubject);
  if (error) throw e2eError("Auth user inspection failed.", EXIT.internal);
  return data.user?.banned_until ?? null;
}

async function currentAccountRows(session) {
  const client = publicClient(thisStatus, session.access_token);
  const { data, error } = await client.rpc("current_account");
  if (error) throw e2eError("current_account failed.", EXIT.internal);
  return Array.isArray(data) ? data : [];
}

async function currentAccountHasAccess(session) {
  const rows = await currentAccountRows(session);
  return rows.some((row) => row?.access_allowed === true);
}

let thisStatus = null;

async function verifyInviteSession(
  {
    status,
    mailpitUrl,
    email,
    sinceMs,
    expectAuthSubject,
    requireAppToken = false,
  },
) {
  const parts = await readInviteParts({ mailpitUrl, email, sinceMs });
  if (requireAppToken && !parts.appToken) {
    throw e2eError("application invitation token missing.", EXIT.client);
  }
  const { data, error } = await publicClient(status).auth.verifyOtp({
    token_hash: parts.tokenHash,
    type: "invite",
  });
  if (error || !data.session || !data.user) {
    throw e2eError("invite verification failed.", EXIT.client);
  }
  if (expectAuthSubject && data.user.id !== expectAuthSubject) {
    throw e2eError(
      "Auth subject mismatch after invite verification.",
      EXIT.client,
    );
  }
  return {
    session: data.session,
    authSubject: data.user.id,
    appToken: parts.appToken,
    safeRedirectRoute: parts.safeRedirectRoute,
  };
}

async function readInviteParts({ mailpitUrl, email, sinceMs }) {
  const message = await waitForMail({ mailpitUrl, email, sinceMs });
  return extractInviteParts(message);
}

async function callFunction(status, functionName, session, body) {
  const response = await fetch(`${status.FUNCTIONS_URL}/${functionName}`, {
    method: "POST",
    headers: {
      Origin: APP_BASE_URL,
      apikey: status.PUBLISHABLE_KEY,
      Authorization: `Bearer ${session.access_token}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });
  const json = await response.json().catch(() => ({}));
  return { status: response.status, json };
}

async function expectFunctionOk(status, functionName, session, body, exitCode) {
  const result = await callFunction(status, functionName, session, body);
  if (
    result.status < 200 || result.status > 299 || result.json?.success !== true
  ) {
    throw e2eError(
      `${functionName} failed safely with HTTP ${result.status}.`,
      exitCode,
    );
  }
  return result.json.data;
}

async function expectFunctionDenied(status, functionName, session, body) {
  const result = await callFunction(status, functionName, session, body);
  if (result.status < 400 || result.json?.success !== false) {
    throw e2eError(`${functionName} was not denied.`, EXIT.authorization);
  }
  return result;
}

async function createAndAcceptClient(
  { status, ownerSession, email, fullName },
) {
  const sinceMs = Date.now();
  const created = await expectFunctionOk(
    status,
    "create-client-invitation",
    ownerSession,
    { email },
    EXIT.client,
  );
  const userId = created.invited_user_id;
  const state = await tableStateByUserId(userId);
  assertScenario(
    state.status === "INVITED" && !state.isActive && state.profileCount === 0 &&
      state.activeRoleCount === 0,
    "Client pre-acceptance state invalid.",
    EXIT.client,
  );
  const verified = await verifyInviteSession({
    status,
    mailpitUrl: status.MAILPIT_URL,
    email,
    sinceMs,
    expectAuthSubject: state.authSubject,
    requireAppToken: true,
  });
  await expectFunctionOk(status, "accept-client-invitation", verified.session, {
    token: verified.appToken,
    full_name: fullName,
  }, EXIT.client);
  const accepted = await tableStateByUserId(userId);
  assertScenario(
    accepted.status === "ACTIVE" && accepted.isActive &&
      accepted.profileCount === 1 && accepted.activeRoleCount === 1 &&
      accepted.invitationStatus === "ACCEPTED",
    "Client acceptance state invalid.",
    EXIT.client,
  );
  const rows = await currentAccountRows.call(null, verified.session);
  assertScenario(
    rows.length === 1 && rows[0].user_type === "CLIENT",
    "Client current_account failed.",
    EXIT.client,
  );
  return { userId, session: verified.session, authSubject: state.authSubject };
}

function assertScenario(condition, message, exitCode) {
  if (!condition) throw e2eError(message, exitCode);
}

async function createStaffFixture(
  { status, admin, ownerUserId, email, roleCode, active = true },
) {
  const link = await admin.auth.admin.generateLink({
    type: "invite",
    email,
    options: { redirectTo: `${APP_BASE_URL}/owner/activate` },
  });
  if (link.error) {
    throw e2eError(
      "staff fixture Auth preparation failed.",
      EXIT.authorization,
    );
  }
  const authSubject = link.data.user.id;
  const userId = crypto.randomUUID();
  await sql(`
insert into app.users(id, auth_subject, email, user_type, status, is_active, created_by, updated_by)
values ('${userId}'::uuid, '${authSubject}'::uuid, '${q(email)}', 'STAFF', '${
    active ? "ACTIVE" : "SUSPENDED"
  }', ${
    active ? "true" : "false"
  }, '${ownerUserId}'::uuid, '${ownerUserId}'::uuid);
insert into app.user_profiles(user_id, full_name, created_by, updated_by)
values ('${userId}'::uuid, 'Fixture Staff', '${ownerUserId}'::uuid, '${ownerUserId}'::uuid);
insert into app.user_roles(user_id, role_code, assigned_by)
values ('${userId}'::uuid, '${q(roleCode)}', '${ownerUserId}'::uuid);`);
  const mailSince = Date.now();
  const delivery = await admin.auth.admin.inviteUserByEmail(email, {
    redirectTo: `${APP_BASE_URL}/owner/activate`,
  });
  if (delivery.error) {
    throw e2eError("staff fixture invite delivery failed.", EXIT.authorization);
  }
  const verified = await verifyInviteSession({
    status,
    mailpitUrl: status.MAILPIT_URL,
    email,
    sinceMs: mailSince,
    expectAuthSubject: authSubject,
  });
  return { userId, authSubject, session: verified.session };
}

async function runScenarios({ status, lines }) {
  thisStatus = status;
  const admin = serviceClient(status);
  const stamp = Date.now();
  const email = (name) => `pkg092-${name}-${stamp}@${TEST_DOMAIN}`;

  lines.push(safeLine("scenario_owner", "start"));
  const ownerEmail = email("owner");
  const ownerMailSince = Date.now();
  const bootstrap = await bootstrapProductionOwner({
    env: {
      SUPABASE_URL: status.API_URL,
      SUPABASE_SERVICE_ROLE_KEY: status.SERVICE_ROLE_KEY,
      APP_BASE_URL,
      BOOTSTRAP_OWNER_EMAIL: ownerEmail,
      BOOTSTRAP_OWNER_FULL_NAME: "Package 09.2 Owner",
      BOOTSTRAP_CONFIRMATION: CONFIRMATION,
    },
    output: () => undefined,
  });
  assertScenario(
    bootstrap.exitCode === 0,
    "first Owner bootstrap failed.",
    EXIT.owner,
  );
  const ownerAuthSubject = bootstrap.lines.find((line) =>
    line.startsWith("auth_user_id=")
  )?.split("=")[1];
  const ownerVerified = await verifyInviteSession({
    status,
    mailpitUrl: status.MAILPIT_URL,
    email: ownerEmail,
    sinceMs: ownerMailSince,
    expectAuthSubject: ownerAuthSubject,
  });
  const ownerUserId = await userIdByAuthSubject(ownerAuthSubject);
  let ownerState = await tableStateByUserId(ownerUserId);
  assertScenario(
    ownerState.status === "INVITED" && !ownerState.isActive &&
      ownerState.profileCount === 1 && ownerState.activeRoleCount === 1 &&
      ownerState.invitationStatus === "PENDING",
    "Owner invited state invalid.",
    EXIT.owner,
  );
  const activate = await publicClient(
    status,
    ownerVerified.session.access_token,
  ).rpc("activate_current_invited_owner");
  if (activate.error) throw e2eError("Owner activation failed.", EXIT.owner);
  ownerState = await tableStateByUserId(ownerUserId);
  assertScenario(
    ownerState.status === "ACTIVE" && ownerState.isActive &&
      ownerState.invitationStatus === "ACCEPTED",
    "Owner active state invalid.",
    EXIT.owner,
  );
  assertScenario(
    (await currentAccountRows.call(null, ownerVerified.session)).length === 1,
    "Owner current_account failed.",
    EXIT.owner,
  );
  const repeatActivation = await publicClient(
    status,
    ownerVerified.session.access_token,
  ).rpc("activate_current_invited_owner");
  assertScenario(
    Boolean(repeatActivation.error),
    "repeated Owner activation should fail.",
    EXIT.owner,
  );
  const secondBootstrap = await bootstrapProductionOwner({
    env: {
      SUPABASE_URL: status.API_URL,
      SUPABASE_SERVICE_ROLE_KEY: status.SERVICE_ROLE_KEY,
      APP_BASE_URL,
      BOOTSTRAP_OWNER_EMAIL: email("owner-second"),
      BOOTSTRAP_OWNER_FULL_NAME: "Second Owner",
      BOOTSTRAP_CONFIRMATION: CONFIRMATION,
    },
    output: () => undefined,
  });
  assertScenario(
    secondBootstrap.exitCode !== 0,
    "second bootstrap should be rejected.",
    EXIT.owner,
  );
  lines.push(safeLine("scenario_owner", "ok"));

  lines.push(safeLine("scenario_client_acceptance", "start"));
  const primaryClient = await createAndAcceptClient({
    status,
    ownerSession: ownerVerified.session,
    email: email("client-primary"),
    fullName: "Primary Client",
  });
  lines.push(safeLine("scenario_client_acceptance", "ok"));

  lines.push(safeLine("scenario_resend", "start"));
  const resendEmail = email("client-resend");
  let resendSince = Date.now();
  const resendCreated = await expectFunctionOk(
    status,
    "create-client-invitation",
    ownerVerified.session,
    { email: resendEmail },
    EXIT.invitationLifecycle,
  );
  const resendUserId = resendCreated.invited_user_id;
  let resendState = await tableStateByUserId(resendUserId);
  const firstInviteCount = await invitationCount(resendUserId);
  const firstInvite = await readInviteParts({
    mailpitUrl: status.MAILPIT_URL,
    email: resendEmail,
    sinceMs: resendSince,
  });
  assertScenario(
    Boolean(firstInvite.appToken),
    "initial resend fixture token missing.",
    EXIT.invitationLifecycle,
  );
  resendSince = Date.now();
  await expectFunctionOk(
    status,
    "resend-client-invitation",
    ownerVerified.session,
    { invited_user_id: resendUserId },
    EXIT.invitationLifecycle,
  );
  assertScenario(
    await invitationCount(resendUserId) === firstInviteCount + 1,
    "resend did not create replacement invitation.",
    EXIT.invitationLifecycle,
  );
  const secondVerified = await verifyInviteSession({
    status,
    mailpitUrl: status.MAILPIT_URL,
    email: resendEmail,
    sinceMs: resendSince,
    expectAuthSubject: resendState.authSubject,
    requireAppToken: true,
  });
  const oldAccept = await callFunction(
    status,
    "accept-client-invitation",
    secondVerified.session,
    { token: firstInvite.appToken, full_name: "Old Token" },
  );
  assertScenario(
    oldAccept.status >= 400,
    "old application token should not work.",
    EXIT.invitationLifecycle,
  );
  await expectFunctionOk(
    status,
    "accept-client-invitation",
    secondVerified.session,
    { token: secondVerified.appToken, full_name: "Resent Client" },
    EXIT.invitationLifecycle,
  );
  resendState = await tableStateByUserId(resendUserId);
  assertScenario(
    resendState.status === "ACTIVE" &&
      resendState.invitationStatus === "ACCEPTED",
    "resent client was not accepted.",
    EXIT.invitationLifecycle,
  );
  lines.push(safeLine("scenario_resend", "ok"));

  lines.push(safeLine("scenario_revoke", "start"));
  const revokeEmail = email("client-revoke");
  const revokeSince = Date.now();
  const revokeCreated = await expectFunctionOk(
    status,
    "create-client-invitation",
    ownerVerified.session,
    { email: revokeEmail },
    EXIT.invitationLifecycle,
  );
  const revokeStateBefore = await tableStateByUserId(
    revokeCreated.invited_user_id,
  );
  const revokeVerified = await verifyInviteSession({
    status,
    mailpitUrl: status.MAILPIT_URL,
    email: revokeEmail,
    sinceMs: revokeSince,
    expectAuthSubject: revokeStateBefore.authSubject,
    requireAppToken: true,
  });
  await expectFunctionOk(
    status,
    "revoke-client-invitation",
    ownerVerified.session,
    {
      invitation_id: revokeCreated.invitation_id,
      revoke_reason: "local e2e revoke",
    },
    EXIT.invitationLifecycle,
  );
  const revokeAccept = await callFunction(
    status,
    "accept-client-invitation",
    revokeVerified.session,
    { token: revokeVerified.appToken, full_name: "Revoked Client" },
  );
  assertScenario(
    revokeAccept.status >= 400,
    "revoked token should not work.",
    EXIT.invitationLifecycle,
  );
  const revokeStateAfter = await tableStateByUserId(
    revokeCreated.invited_user_id,
  );
  assertScenario(
    revokeStateAfter.status === "INVITED" &&
      revokeStateAfter.invitationStatus === "REVOKED" &&
      revokeStateAfter.profileCount === 0 &&
      revokeStateAfter.activeRoleCount === 0,
    "revocation state invalid.",
    EXIT.invitationLifecycle,
  );
  lines.push(safeLine("scenario_revoke", "ok"));

  lines.push(safeLine("scenario_lifecycle", "start"));
  await expectFunctionOk(
    status,
    "suspend-client-account",
    ownerVerified.session,
    { client_user_id: primaryClient.userId, reason: "local e2e suspend" },
    EXIT.lifecycle,
  );
  let lifecycleState = await tableStateByUserId(primaryClient.userId);
  assertScenario(
    lifecycleState.status === "SUSPENDED" && !lifecycleState.isActive,
    "suspend state invalid.",
    EXIT.lifecycle,
  );
  assertScenario(
    Boolean(await authBanState(primaryClient.authSubject, admin)),
    "Auth ban missing after suspend.",
    EXIT.lifecycle,
  );
  assertScenario(
    !(await currentAccountHasAccess(primaryClient.session)),
    "suspended client retained current_account access.",
    EXIT.lifecycle,
  );
  await expectFunctionOk(
    status,
    "reactivate-client-account",
    ownerVerified.session,
    { client_user_id: primaryClient.userId, reason: "local e2e reactivate" },
    EXIT.lifecycle,
  );
  lifecycleState = await tableStateByUserId(primaryClient.userId);
  assertScenario(
    lifecycleState.status === "ACTIVE" && lifecycleState.isActive,
    "reactivation state invalid.",
    EXIT.lifecycle,
  );
  assertScenario(
    !await authBanState(primaryClient.authSubject, admin),
    "Auth ban not removed after reactivation.",
    EXIT.lifecycle,
  );
  assertScenario(
    (await currentAccountRows.call(null, primaryClient.session)).length === 1,
    "reactivated client lacks current_account access.",
    EXIT.lifecycle,
  );

  const disabledClient = await createAndAcceptClient({
    status,
    ownerSession: ownerVerified.session,
    email: email("client-disabled"),
    fullName: "Disabled Client",
  });
  await expectFunctionOk(
    status,
    "disable-client-account",
    ownerVerified.session,
    { client_user_id: disabledClient.userId, reason: "local e2e disable" },
    EXIT.lifecycle,
  );
  const disabledState = await tableStateByUserId(disabledClient.userId);
  assertScenario(
    disabledState.status === "DISABLED" && !disabledState.isActive,
    "disabled state invalid.",
    EXIT.lifecycle,
  );
  assertScenario(
    Boolean(await authBanState(disabledClient.authSubject, admin)),
    "Auth ban missing after disable.",
    EXIT.lifecycle,
  );
  assertScenario(
    !(await currentAccountHasAccess(disabledClient.session)),
    "disabled client retained current_account access.",
    EXIT.lifecycle,
  );
  await expectFunctionDenied(
    status,
    "reactivate-client-account",
    ownerVerified.session,
    { client_user_id: disabledClient.userId, reason: "terminal disabled" },
  );
  lines.push(safeLine("scenario_lifecycle", "ok"));

  lines.push(safeLine("scenario_authorization", "start"));
  const beforeMissingMalformedLogs = Number(
    await sql(
      "select count(*)::int from app.activity_logs where action = 'denied_privileged_operation'",
    ),
  );
  const missing = await fetch(
    `${status.FUNCTIONS_URL}/create-client-invitation`,
    {
      method: "POST",
      headers: {
        Origin: APP_BASE_URL,
        apikey: status.PUBLISHABLE_KEY,
        "content-type": "application/json",
      },
      body: JSON.stringify({ email: email("missing-jwt") }),
    },
  );
  assertScenario(
    missing.status === 401,
    "missing JWT was not rejected.",
    EXIT.authorization,
  );
  const malformed = await fetch(
    `${status.FUNCTIONS_URL}/create-client-invitation`,
    {
      method: "POST",
      headers: {
        Origin: APP_BASE_URL,
        apikey: status.PUBLISHABLE_KEY,
        Authorization: "Bearer malformed",
        "content-type": "application/json",
      },
      body: JSON.stringify({ email: email("malformed-jwt") }),
    },
  );
  assertScenario(
    malformed.status === 401,
    "malformed JWT was not rejected.",
    EXIT.authorization,
  );
  assertScenario(
    Number(
      await sql(
        "select count(*)::int from app.activity_logs where action = 'denied_privileged_operation'",
      ),
    ) === beforeMissingMalformedLogs,
    "missing/malformed JWT created denial log.",
    EXIT.authorization,
  );

  await expectFunctionDenied(
    status,
    "create-client-invitation",
    primaryClient.session,
    { email: email("client-denied") },
  );
  await expectFunctionDenied(
    status,
    "suspend-client-account",
    primaryClient.session,
    { client_user_id: disabledClient.userId, reason: "client denied" },
  );
  await expectFunctionDenied(
    status,
    "reactivate-client-account",
    primaryClient.session,
    { client_user_id: disabledClient.userId, reason: "client denied" },
  );
  await expectFunctionDenied(
    status,
    "disable-client-account",
    primaryClient.session,
    { client_user_id: disabledClient.userId, reason: "client denied" },
  );
  const reserved = await createStaffFixture({
    status,
    admin,
    ownerUserId,
    email: email("reserved"),
    roleCode: "project_manager",
    active: true,
  });
  await expectFunctionDenied(
    status,
    "create-client-invitation",
    reserved.session,
    { email: email("reserved-denied") },
  );
  const inactiveOwner = await createStaffFixture({
    status,
    admin,
    ownerUserId,
    email: email("inactive-owner"),
    roleCode: "owner_admin",
    active: false,
  });
  await expectFunctionDenied(
    status,
    "create-client-invitation",
    inactiveOwner.session,
    { email: email("inactive-denied") },
  );
  const denialCount = Number(
    await sql(
      "select count(*)::int from app.activity_logs where action = 'denied_privileged_operation'",
    ),
  );
  assertScenario(
    denialCount > beforeMissingMalformedLogs,
    "durable denial logs were not created.",
    EXIT.authorization,
  );
  const unsafeMetadataHits = Number(
    await sql(
      "select count(*)::int from app.activity_logs where action = 'denied_privileged_operation' and metadata::text ~ '(Bearer|token=|access_token|refresh_token|service_role|raw_body)'",
    ),
  );
  assertScenario(
    unsafeMetadataHits === 0,
    "denial metadata contains unsafe values.",
    EXIT.authorization,
  );
  lines.push(safeLine("scenario_authorization", "ok"));
}

export async function runPackage092E2ELocal(
  { root = Deno.cwd(), output = console.log } = {},
) {
  const lines = [];
  let status = null;
  let serve = null;
  const envFile = `${
    Deno.env.get("TEMP") ?? Deno.env.get("TMP") ?? "."
  }\\${TEMP_ENV_NAME}`;
  try {
    lines.push(safeLine("package_09_2_e2e", "start"));
    await runCommand("supabase", ["db", "reset", "--local"], {
      cwd: root,
      exitCode: EXIT.supabase,
    });
    const statusRaw = await runCommand("supabase", ["status"], {
      cwd: root,
      exitCode: EXIT.supabase,
    });
    status = parseSupabaseStatus(statusRaw);
    await clearMailpit(fetch, status.MAILPIT_URL);
    await writeNoBomEnvFile(envFile);
    serve = await startFunctionsServe({ cwd: root, envFile });
    lines.push(safeLine("edge_functions", "ready"));
    await runScenarios({ status, lines });
    lines.push(safeLine("package_09_2_e2e", "ok"));
    return { exitCode: EXIT.ok, lines };
  } catch (error) {
    const exitCode = Number.isInteger(error?.exitCode)
      ? error.exitCode
      : EXIT.internal;
    lines.push(safeLine("package_09_2_e2e", "failed"));
    lines.push(safeLine("error", error?.message ?? "unexpected failure"));
    return { exitCode, lines };
  } finally {
    try {
      await cleanupAll({ status, serve, envFile, root, reset: true, lines });
    } catch (error) {
      lines.push(safeLine("cleanup_error", error?.message ?? "cleanup failed"));
    }
    for (const line of lines) output(line);
  }
}

export async function main() {
  const result = await runPackage092E2ELocal();
  Deno.exit(result.exitCode);
}

if (import.meta.main) {
  await main();
}
