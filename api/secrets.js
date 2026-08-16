'use strict';

// =============================================================================
// secrets.js — resolve DB credentials from AWS Secrets Manager at boot.
// Drop this into your app (next to server.js / database.js) and implement it.
//
// TODO (C3): implement loadDbCredentials() using @aws-sdk/client-secrets-manager
// (add it to package.json). Requirements:
//   * Configure the client with endpoint: process.env.AWS_ENDPOINT_URL. On real
//     AWS this env var is unset and the SDK talks to AWS. THERE MUST BE NO
//     `if (isLocalStack)` BRANCH.
//   * GetSecretValue for process.env.DB_SECRET_ARN; parse the JSON envelope
//     { engine, username, password, host, port, dbname }.
//   * Cache the parsed value + the returned ARN and VersionId.
//   * Log ONLY the ARN + version — never the password.
//   * If DB_SECRET_ARN is unset, fall back to MYSQL_* env vars with source
//     { arn: 'env', versionId: 'n/a' } so plain local runs still work.
//   * Export getSecretSource() -> { arn, versionId } (no secret values) for the
//     /debug/secret-source endpoint your verify step checks.
// =============================================================================

async function loadDbCredentials() {
  throw new Error('TODO: implement C3 — resolve creds from Secrets Manager');
}

function getSecretSource() {
  return { arn: 'TODO', versionId: 'TODO' };
}

module.exports = { loadDbCredentials, getSecretSource };
