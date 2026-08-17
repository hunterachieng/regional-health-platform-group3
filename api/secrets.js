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
  };
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

  // Log ARN + version only — never the password.
  // eslint-disable-next-line no-console
  console.log(
    `DB credentials loaded from Secrets Manager arn=${secretSource.arn} version=${secretSource.versionId}`
  );

  return {
    host: envelope.host,
    port: Number(envelope.port),
    user: envelope.username,
    password: envelope.password,
    database: envelope.dbname,
  };
}

function getSecretSource() {
  return { ...secretSource };
}

module.exports = { loadDbCredentials, getSecretSource };
