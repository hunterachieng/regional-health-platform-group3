'use strict';

/**
 * database.js
 * -----------------------------------------------------------------------------
 * Connection factories for MySQL and MongoDB.
 * MySQL pool is created at boot after credentials are resolved (secrets.js).
 */

const mysql = require('mysql2/promise');
const { MongoClient } = require('mongodb');

const MONGO_URI = process.env.MONGO_URI || 'mongodb://mongo-db:27017';
const MONGO_DB_NAME = process.env.MONGO_DB || 'capacity_lab';

const POOL_OPTIONS = {
  waitForConnections: true,
  connectionLimit: Number(process.env.MYSQL_CONNECTION_LIMIT || 20),
  queueLimit: 0,
  connectTimeout: 10_000,
  maxIdle: Number(process.env.MYSQL_CONNECTION_LIMIT || 20),
  idleTimeout: 60_000,
  enableKeepAlive: true,
};

let pool;
let mysqlReady = false;

async function initDatabase(credentials) {
  if (pool) {
    await pool.end();
    pool = undefined;
    mysqlReady = false;
  }

  pool = mysql.createPool({
    ...POOL_OPTIONS,
    host: credentials.host,
    port: credentials.port,
    user: credentials.user,
    password: credentials.password,
    database: credentials.database,
  });

  const conn = await pool.getConnection();
  try {
    await conn.ping();
    mysqlReady = true;
  } finally {
    conn.release();
  }
}

function getPool() {
  if (!pool) {
    throw new Error('MySQL pool not initialized — call initDatabase() at boot');
  }
  return pool;
}

function isPoolSaturated() {
  if (!pool || !pool.pool) return false;
  const internal = pool.pool;
  const queueLen = internal._connectionQueue?.length || 0;
  const freeLen = internal._freeConnections?.length || 0;
  return queueLen > 0 && freeLen === 0;
}

async function checkDbReadiness() {
  if (!pool) {
    return { ready: false, reason: 'pool_not_initialized' };
  }
  if (!mysqlReady) {
    return { ready: false, reason: 'mysql_not_ready' };
  }
  if (isPoolSaturated()) {
    return { ready: false, reason: 'pool_saturated' };
  }

  let conn;
  try {
    conn = await pool.getConnection();
    await conn.ping();
    return { ready: true };
  } catch (err) {
    mysqlReady = false;
    return { ready: false, reason: err.code || 'db_unreachable' };
  } finally {
    if (conn) conn.release();
  }
}

// ---------------------------------------------------------------------------
// MongoDB client (singleton, lazily connected — not part of /readyz for A2)
// ---------------------------------------------------------------------------
let mongoClient;
let mongoDb;

async function getMongo() {
  if (!mongoDb) {
    mongoClient = new MongoClient(MONGO_URI, {
      maxPoolSize: 5,
      serverSelectionTimeoutMS: 5_000,
    });
    await mongoClient.connect();
    mongoDb = mongoClient.db(MONGO_DB_NAME);
  }
  return mongoDb;
}

async function closeAll() {
  mysqlReady = false;
  if (pool) {
    try { await pool.end(); } catch (_) { /* ignore */ }
    pool = undefined;
  }
  if (mongoClient) {
    try { await mongoClient.close(); } catch (_) { /* ignore */ }
    mongoClient = undefined;
    mongoDb = undefined;
  }
}

module.exports = {
  MONGO_URI,
  MONGO_DB_NAME,
  initDatabase,
  getPool,
  checkDbReadiness,
  getMongo,
  closeAll,
};
