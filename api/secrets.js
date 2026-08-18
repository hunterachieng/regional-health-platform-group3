'use strict';

const {
  SecretsManagerClient,
  GetSecretValueCommand,
} = require('@aws-sdk/client-secrets-manager');

let secretSource = { arn: 'env', versionId: 'n/a' };

function buildSecretsClient() {
  const config = { region: process.env.AWS_REGION || 'us-east-1' };
  if (process.env.AWS_ENDPOINT_URL) {
    config.endpoint = process.env.AWS_ENDPOINT_URL;
  }
  return new SecretsManagerClient(config);
}

function credentialsFromEnv() {
  return {
    host: process.env.MYSQL_HOST || 'mysql-db',
    port: Number(process.env.MYSQL_PORT || 3306),
    user: process.env.MYSQL_USER || 'root',
    password: process.env.MYSQL_PASSWORD || 'labpassword',
    database: process.env.MYSQL_DATABASE || 'capacity_lab',
    // Local docker-compose MySQL speaks plaintext, so no CA by default. Set
    // MYSQL_CA_CERT if you point local dev at a TLS-only server.
    caCert: normalizeCaCert(process.env.MYSQL_CA_CERT),
  };
}

/**
 * Return a usable PEM string, or undefined if there is no cert.
 *
 * A PEM is multi-line. On the way to the app it passes through a GitHub Actions
 * secret, a TF_VAR, jsonencode(), and Secrets Manager — and newlines do not
 * always survive that trip intact. So accept either form:
 *   - a real PEM (contains "BEGIN CERTIFICATE")
 *   - the same PEM base64-encoded, which is newline-safe end to end
 * Getting this wrong surfaces as an opaque TLS handshake failure rather than a
 * clear error, which is why it is worth handling explicitly.
 */
function normalizeCaCert(raw) {
  if (!raw || raw.trim() === '') return undefined;
  if (raw.includes('BEGIN CERTIFICATE')) return raw;

  const decoded = Buffer.from(raw, 'base64').toString('utf8');
  if (decoded.includes('BEGIN CERTIFICATE')) return decoded;

  throw new Error(
    'CA certificate is neither a PEM nor base64-encoded PEM — check aiven_ca_cert'
  );
}

async function loadDbCredentials() {
  const secretArn = process.env.DB_SECRET_ARN;
  if (!secretArn) {
    secretSource = { arn: 'env', versionId: 'n/a' };
    return credentialsFromEnv();
  }

  const client = buildSecretsClient();
  const response = await client.send(
    new GetSecretValueCommand({ SecretId: secretArn })
  );

  const envelope = JSON.parse(response.SecretString);
  secretSource = {
    arn: response.ARN || secretArn,
    versionId: response.VersionId || 'unknown',
  };

  const caCert = normalizeCaCert(envelope.ca_cert);

  // Log ARN + version only — never the password. Whether TLS material arrived
  // is logged as a boolean so boot.log proves the connection is encrypted
  // without printing the certificate.
  // eslint-disable-next-line no-console
  console.log(
    `DB credentials loaded from Secrets Manager arn=${secretSource.arn} ` +
      `version=${secretSource.versionId} tls_ca_present=${Boolean(caCert)}`
  );

  return {
    host: envelope.host,
    port: Number(envelope.port),
    user: envelope.username,
    password: envelope.password,
    database: envelope.dbname,
    // Aiven refuses plaintext connections, so this is required in the cloud
    // path. modules/data puts it in the envelope under ca_cert.
    caCert,
  };
}

function getSecretSource() {
  return { ...secretSource };
}

module.exports = { loadDbCredentials, getSecretSource };
