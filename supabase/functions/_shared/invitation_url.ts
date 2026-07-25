import { validationFailed } from "./errors.ts";

export function invitationUrl(
  appBaseUrl: string,
  applicationToken: string,
): URL {
  if (!applicationToken || /[=&?#/\s]/.test(applicationToken)) {
    throw validationFailed("Invitation token is invalid.");
  }
  const url = new URL(appBaseUrl);
  url.pathname = "/accept-invitation";
  url.search = "";
  url.searchParams.set("token", applicationToken);
  url.hash = "";
  return url;
}
