'use strict';

/**
 * server.js
 * -----------------------------------------------------------------------------
 * Express API for the Regional Health admissions & patient-lookup service.
 *
 * Endpoints:
 *   GET  /api/patients/recent        Recent patients widget
 *   GET  /api/patients/search        Patient lookup by last name
 *   POST /api/hospitals/:id/admit    Admit a patient (decrement bed count)
 *   GET  /api/patients/export        Full patient export for the analytics team
 *   GET  /api/audit/ping             Mongo audit-store health probe
 *   GET  /metrics                    Prometheus metrics
 */

const express = require('express');
const client = require('prom-client');
const { getPool, getMongo } = require('./database');

const app = express();
app.use(express.json());

const PORT = Number(process.env.PORT || 3000);

// ---------------------------------------------------------------------------
// Prometheus metrics
// ---------------------------------------------------------------------------
const register = new client.Registry();
register.setDefaultLabels({ app: 'capacity-api' });

// Default process/GC/heap metrics.
client.collectDefaultMetrics({ register, gcDurationBuckets: [0.001, 0.01, 0.1, 1, 2, 5] });

const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10],
  registers: [register],
});

const httpRequestsTotal = new client.Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status_code'],
  registers: [register],
});

const dbErrorsTotal = new client.Counter({
  name: 'db_errors_total',
  help: 'Total number of database errors by type',
  labelNames: ['route', 'code'],
  registers: [register],
});

const registryNotifyFailuresTotal = new client.Counter({
  name: 'registry_notify_failures_total',
  help: 'Registry notifications that failed after all retry attempts (DB already committed)',
  labelNames: ['hospital_id'],
  registers: [register],
});

// Per-request timing + counting middleware
app.use((req, res, next) => {
  const end = httpRequestDuration.startTimer();
  res.on('finish', () => {
    const route = req.route ? req.baseUrl + req.route.path : req.path;
    const labels = { method: req.method, route, status_code: res.statusCode };
    end(labels);
    httpRequestsTotal.inc(labels);
  });
  next();
});

// ---------------------------------------------------------------------------
// Health & metrics
// ---------------------------------------------------------------------------
app.get('/health', (_req, res) => res.json({ status: 'ok' }));

app.get('/metrics', async (_req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// ---------------------------------------------------------------------------
// Recent patients widget
// ---------------------------------------------------------------------------
app.get('/api/patients/recent', async (_req, res) => {
  try {
    const pool = getPool();
    const [rows] = await pool.query(
      'SELECT * FROM patients ORDER BY id DESC LIMIT 50'
    );
    res.json({ count: rows.length, data: rows });
  } catch (err) {
    dbErrorsTotal.inc({ route: '/api/patients/recent', code: err.code || 'UNKNOWN' });
    res.status(500).json({ error: err.code || 'ERROR', message: err.message });
  }
});

// ---------------------------------------------------------------------------
// Patient lookup by last name
// ---------------------------------------------------------------------------
app.get('/api/patients/search', async (req, res) => {
  const lastName = req.query.lastName || '';
  try {
    const pool = getPool();
    const [rows] = await pool.query(
      'SELECT id, first_name, last_name, email FROM patients WHERE last_name = ? LIMIT 100',
      [lastName]
    );
    res.json({ count: rows.length, lastName, data: rows });
  } catch (err) {
    dbErrorsTotal.inc({ route: '/api/patients/search', code: err.code || 'UNKNOWN' });
    res.status(500).json({ error: err.code || 'ERROR', message: err.message });
  }
});

// ---------------------------------------------------------------------------
// Admit a patient to a hospital (decrement available beds).
// Commit the bed deduction first, then notify the registry outside the
// transaction so we don't hold row locks during the external call.
// ---------------------------------------------------------------------------
app.post('/api/hospitals/:id/admit', async (req, res) => {
  const hospitalId = Number(req.params.id);
  const pool = getPool();
  let conn;
  try {
    conn = await pool.getConnection();
    await conn.beginTransaction();

    const [result] = await conn.query(
      'UPDATE hospitals SET available_beds = available_beds - 1 WHERE id = ? AND available_beds > 0',
      [hospitalId]
    );
    if (result.affectedRows === 0) {
      await conn.rollback();
      return res.status(409).json({
        error: 'NO_BEDS_AVAILABLE',
        message: 'Hospital has no available beds',
      });
    }
    await conn.commit();
  } catch (err) {
    if (conn) {
      try { await conn.rollback(); } catch (_) { /* ignore */ }
    }
    dbErrorsTotal.inc({ route: '/api/hospitals/:id/admit', code: err.code || 'UNKNOWN' });
    return res.status(500).json({ error: err.code || 'ERROR', message: err.message });
  } finally {
    if (conn) conn.release();
  }

  // Post-commit: retry registry sync. DB is already committed — do not fail
  // the admission if the external call is flaky (avoid double-deduct on retry).
  let registrySync = 'ok';
  try {
    const { attempts } = await notifyBedRegistryWithRetry(hospitalId);
    if (attempts > 1) registrySync = 'ok_after_retry';
  } catch (err) {
    registryNotifyFailuresTotal.inc({ hospital_id: String(hospitalId) });
    // eslint-disable-next-line no-console
    console.error(
      `Registry notify failed for hospital ${hospitalId} after retries:`,
      err.message
    );
    registrySync = 'pending';
  }

  res.json({ status: 'admitted', hospitalId, registrySync });
});

const REGISTRY_MAX_RETRIES = Number(process.env.REGISTRY_MAX_RETRIES || 3);
const REGISTRY_RETRY_BASE_MS = Number(process.env.REGISTRY_RETRY_BASE_MS || 100);
// Lab only: simulate N failed notify attempts per hospital before succeeding.
const REGISTRY_SIMULATED_FAILURES = Number(process.env.REGISTRY_SIMULATED_FAILURES || 0);

const registrySimulatedFailureCounts = new Map();

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// Stand-in for the external registry client used by the admit flow.
async function notifyBedRegistry(hospitalId) {
  if (REGISTRY_SIMULATED_FAILURES > 0) {
    const failures = registrySimulatedFailureCounts.get(hospitalId) || 0;
    if (failures < REGISTRY_SIMULATED_FAILURES) {
      registrySimulatedFailureCounts.set(hospitalId, failures + 1);
      throw new Error('Registry unavailable (simulated)');
    }
  }
  await sleep(500);
}

async function notifyBedRegistryWithRetry(hospitalId) {
  let lastErr;
  for (let attempt = 1; attempt <= REGISTRY_MAX_RETRIES; attempt++) {
    try {
      await notifyBedRegistry(hospitalId);
      return { attempts: attempt };
    } catch (err) {
      lastErr = err;
      if (attempt < REGISTRY_MAX_RETRIES) {
        await sleep(REGISTRY_RETRY_BASE_MS * attempt);
      }
    }
  }
  throw lastErr;
}

// ---------------------------------------------------------------------------
// Full patient export for the analytics/ETL team.
// Read in batches (keyset pagination) and stream JSON to the response so at
// most BATCH_SIZE rows sit in memory at once — O(batch) not O(N).
// Cap concurrent exports so 50 callers cannot each buffer a full payload.
// ---------------------------------------------------------------------------
const EXPORT_BATCH_SIZE = 500;

// Serialize exports — one in flight at a time so memory stays within the 160MB cap.
let exportQueue = Promise.resolve();

app.get('/api/patients/export', (_req, res) => {
  const job = exportQueue.then(() => streamPatientExport(res));
  exportQueue = job.catch(() => {});
  job.catch(() => {});
});

async function streamPatientExport(res) {
  const pool = getPool();
  try {
    res.setHeader('Content-Type', 'application/json');
    res.write('{"data":[');

    let first = true;
    let count = 0;
    let lastId = 0;

    while (true) {
      const [rows] = await pool.query(
        'SELECT * FROM patients WHERE id > ? ORDER BY id LIMIT ?',
        [lastId, EXPORT_BATCH_SIZE]
      );
      if (rows.length === 0) break;

      for (const row of rows) {
        if (!first) res.write(',');
        first = false;
        count++;
        lastId = row.id;
        res.write(JSON.stringify(row));
      }

      if (rows.length < EXPORT_BATCH_SIZE) break;
    }

    res.write(`],"count":${count}}`);
    res.end();
  } catch (err) {
    dbErrorsTotal.inc({ route: '/api/patients/export', code: err.code || 'UNKNOWN' });
    if (!res.headersSent) {
      res.status(500).json({ error: err.code || 'ERROR', message: err.message });
    } else {
      res.destroy();
    }
  }
}

// ---------------------------------------------------------------------------
// Mongo audit-store health probe
// ---------------------------------------------------------------------------
app.get('/api/audit/ping', async (_req, res) => {
  try {
    const db = await getMongo();
    const result = await db.command({ ping: 1 });
    res.json({ mongo: result });
  } catch (err) {
    res.status(500).json({ error: 'MONGO_ERROR', message: err.message });
  }
});

// ---------------------------------------------------------------------------
// Boot
// ---------------------------------------------------------------------------
app.listen(PORT, () => {
  // eslint-disable-next-line no-console
  console.log(`capacity-api listening on :${PORT} (metrics at /metrics)`);
});
