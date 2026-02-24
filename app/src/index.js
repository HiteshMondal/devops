// /app/src/index.js
'use strict';

const express = require('express');
const morgan  = require('morgan');
const promClient = require('prom-client');
const http   = require('http');
const path   = require('path');
const os     = require('os');

const app    = express();
const server = http.createServer(app);
const PORT   = process.env.APP_PORT || 3000;

//  PROMETHEUS METRICS
const register = new promClient.Registry();

promClient.collectDefaultMetrics({
  register,
  prefix: 'nodejs_',
  gcDurationBuckets: [0.001, 0.01, 0.1, 1, 2, 5],
});

const httpRequestDuration = new promClient.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.001, 0.005, 0.015, 0.05, 0.1, 0.5, 1, 5],
});

const httpRequestTotal = new promClient.Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status_code'],
});

const activeConnections = new promClient.Gauge({
  name: 'http_active_connections',
  help: 'Number of active HTTP connections',
});

const appUptime = new promClient.Gauge({
  name: 'app_uptime_seconds',
  help: 'Application uptime in seconds',
});

const appInfo = new promClient.Gauge({
  name: 'app_info',
  help: 'Application information',
  labelNames: ['version', 'name', 'env'],
});

const memoryUsedGauge = new promClient.Gauge({
  name: 'app_memory_used_bytes',
  help: 'Heap memory used by the process',
});

const requestErrorRate = new promClient.Counter({
  name: 'http_errors_total',
  help: 'Total HTTP error responses (4xx/5xx)',
  labelNames: ['method', 'route', 'status_code'],
});

register.registerMetric(httpRequestDuration);
register.registerMetric(httpRequestTotal);
register.registerMetric(activeConnections);
register.registerMetric(appUptime);
register.registerMetric(appInfo);
register.registerMetric(memoryUsedGauge);
register.registerMetric(requestErrorRate);

appInfo.set({
  version: process.env.APP_VERSION || '2.0.0',
  name:    process.env.APP_NAME    || 'devops-app',
  env:     process.env.NODE_ENV    || 'development',
}, 1);

//  IN-MEMORY METRICS RING BUFFER  (for live dashboard)
const RING_SIZE = 60;   // 60 samples → 1 min of history at 1s interval

const ring = {
  timestamps:   [],
  cpu:          [],
  memPct:       [],
  rps:          [],   // requests per second
  p99:          [],   // estimated p99 latency (ms)
  statusCounts: [],   // { '2xx':n, '4xx':n, '5xx':n } per tick
};

let prevCpuUsage = process.cpuUsage();
let prevCpuTime  = Date.now();
let tickReqCount = 0;
let tickDurSum   = 0;
let tickDurCount = 0;
let tick2xx = 0, tick4xx = 0, tick5xx = 0;

function pushRing(key, value) {
  ring[key].push(value);
  if (ring[key].length > RING_SIZE) ring[key].shift();
}

const startTime = Date.now();

setInterval(() => {
  const now       = Date.now();
  const totalMem  = os.totalmem();
  const freeMem   = os.freemem();
  const memUsed   = totalMem - freeMem;
  const memPct    = Math.round((memUsed / totalMem) * 100);

  // CPU delta
  const curCpu   = process.cpuUsage(prevCpuUsage);
  const elapsed  = (now - prevCpuTime) * 1000; // µs
  const cpuPct   = Math.min(100, Math.round(((curCpu.user + curCpu.system) / elapsed) * 100));
  prevCpuUsage   = process.cpuUsage();
  prevCpuTime    = now;

  const avgLatency = tickDurCount > 0 ? Math.round((tickDurSum / tickDurCount) * 1000) : 0;

  pushRing('timestamps',   now);
  pushRing('cpu',          cpuPct);
  pushRing('memPct',       memPct);
  pushRing('rps',          tickReqCount);
  pushRing('p99',          avgLatency);
  pushRing('statusCounts', { '2xx': tick2xx, '4xx': tick4xx, '5xx': tick5xx });

  // prometheus gauges
  appUptime.set((now - startTime) / 1000);
  memoryUsedGauge.set(process.memoryUsage().heapUsed);

  // reset tick counters
  tickReqCount = 0;
  tickDurSum   = 0;
  tickDurCount = 0;
  tick2xx = 0; tick4xx = 0; tick5xx = 0;
}, 1000);

// ─────────────────────────────────────────────
//  MIDDLEWARE
// ─────────────────────────────────────────────
app.use(morgan('combined'));
app.use(express.json());

app.use((req, res, next) => {
  activeConnections.inc();
  const start = Date.now();

  res.on('finish', () => {
    const duration = (Date.now() - start) / 1000;
    const route    = req.route ? req.route.path : req.path;
    const labels   = { method: req.method, route, status_code: res.statusCode };

    httpRequestDuration.observe(labels, duration);
    httpRequestTotal.inc(labels);
    activeConnections.dec();

    // tick counters (skip /metrics polling)
    if (route !== '/metrics') {
      tickReqCount++;
      tickDurSum   += duration;
      tickDurCount++;
    }
    if (res.statusCode >= 500)      { tick5xx++; requestErrorRate.inc(labels); }
    else if (res.statusCode >= 400) { tick4xx++; requestErrorRate.inc(labels); }
    else                            { tick2xx++; }
  });

  next();
});

//  DASHBOARD HTML  (single-file, no build step)
const DASHBOARD_HTML = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>DevOps Dashboard</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Share+Tech+Mono&family=Barlow:wght@300;400;600;700&family=Barlow+Condensed:wght@400;700&display=swap" rel="stylesheet">
<style>
/* ── RESET & ROOT ── */
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

:root {
  --bg0:   #080c10;
  --bg1:   #0d1117;
  --bg2:   #131920;
  --bg3:   #1a2230;
  --border: #1e3040;
  --accent: #00e5ff;
  --accent2: #00ff9d;
  --accent3: #ff6b35;
  --warn:   #ffd600;
  --danger: #ff1744;
  --text1:  #e8f4f8;
  --text2:  #7a9bb0;
  --text3:  #3d5a6e;
  --mono:   'Share Tech Mono', monospace;
  --sans:   'Barlow', sans-serif;
  --cond:   'Barlow Condensed', sans-serif;
}

html, body {
  background: var(--bg0);
  color: var(--text1);
  font-family: var(--sans);
  font-size: 14px;
  min-height: 100vh;
  overflow-x: hidden;
}

/* ── SCANLINE OVERLAY ── */
body::before {
  content: '';
  position: fixed; inset: 0;
  background: repeating-linear-gradient(
    0deg,
    transparent,
    transparent 2px,
    rgba(0,229,255,0.012) 2px,
    rgba(0,229,255,0.012) 4px
  );
  pointer-events: none;
  z-index: 9999;
}

/* ── TOP NAV ── */
header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0 24px;
  height: 56px;
  background: var(--bg1);
  border-bottom: 1px solid var(--border);
  position: sticky; top: 0; z-index: 100;
}

.logo {
  display: flex; align-items: center; gap: 10px;
}
.logo-icon {
  width: 32px; height: 32px;
  background: linear-gradient(135deg, var(--accent), var(--accent2));
  clip-path: polygon(50% 0%, 100% 25%, 100% 75%, 50% 100%, 0% 75%, 0% 25%);
  animation: pulse-hex 3s ease-in-out infinite;
}
@keyframes pulse-hex {
  0%, 100% { opacity: 1; transform: scale(1); }
  50%       { opacity: .8; transform: scale(.96); }
}
.logo-text {
  font-family: var(--cond);
  font-size: 18px;
  font-weight: 700;
  letter-spacing: 3px;
  text-transform: uppercase;
  color: var(--accent);
}
.logo-sub {
  font-family: var(--mono);
  font-size: 10px;
  color: var(--text3);
  letter-spacing: 2px;
}

.header-right {
  display: flex; align-items: center; gap: 20px;
}
.live-badge {
  display: flex; align-items: center; gap: 6px;
  font-family: var(--mono); font-size: 11px;
  color: var(--accent2); letter-spacing: 1px;
}
.live-dot {
  width: 7px; height: 7px;
  background: var(--accent2);
  border-radius: 50%;
  animation: blink 1s step-end infinite;
  box-shadow: 0 0 8px var(--accent2);
}
@keyframes blink { 0%,100%{opacity:1} 50%{opacity:.2} }

.header-time {
  font-family: var(--mono); font-size: 12px; color: var(--text2);
}

/* ── LAYOUT ── */
.page { padding: 20px 24px 40px; }

.grid-top {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 16px;
  margin-bottom: 20px;
}
.grid-mid {
  display: grid;
  grid-template-columns: 2fr 1fr;
  gap: 16px;
  margin-bottom: 20px;
}
.grid-bot {
  display: grid;
  grid-template-columns: 1fr 1fr 1fr;
  gap: 16px;
}

/* ── CARD ── */
.card {
  background: var(--bg1);
  border: 1px solid var(--border);
  border-radius: 4px;
  padding: 16px 20px;
  position: relative;
  overflow: hidden;
  transition: border-color .2s;
}
.card:hover { border-color: var(--accent); }
.card::after {
  content: '';
  position: absolute; top: 0; left: 0; right: 0; height: 2px;
  background: linear-gradient(90deg, transparent, var(--accent), transparent);
  opacity: 0;
  transition: opacity .3s;
}
.card:hover::after { opacity: 1; }

.card-label {
  font-family: var(--mono); font-size: 10px;
  letter-spacing: 2px; text-transform: uppercase;
  color: var(--text3); margin-bottom: 8px;
}
.card-value {
  font-family: var(--cond); font-size: 36px; font-weight: 700;
  line-height: 1; color: var(--text1);
}
.card-value .unit {
  font-size: 14px; font-weight: 400; color: var(--text2); margin-left: 4px;
}
.card-delta {
  font-family: var(--mono); font-size: 11px;
  color: var(--text3); margin-top: 6px;
}
.card-delta.up   { color: var(--accent2); }
.card-delta.down { color: var(--danger); }

.card-accent-bar {
  position: absolute; bottom: 0; left: 0;
  height: 3px; background: var(--accent);
  transition: width .6s ease;
}

/* ── SECTION TITLE ── */
.section-title {
  font-family: var(--cond); font-size: 11px; font-weight: 700;
  letter-spacing: 3px; text-transform: uppercase;
  color: var(--text3); margin-bottom: 14px;
  display: flex; align-items: center; gap: 10px;
}
.section-title::after {
  content: ''; flex: 1; height: 1px; background: var(--border);
}

/* ── CANVAS CHARTS ── */
.chart-wrap {
  position: relative; height: 180px; margin-top: 4px;
}
.chart-wrap canvas { width: 100% !important; }

/* ── DONUT ── */
.donut-wrap {
  display: flex; flex-direction: column; align-items: center;
  justify-content: center; gap: 16px; height: 200px;
}
.donut-canvas-wrap { position: relative; width: 150px; height: 150px; }
.donut-center {
  position: absolute; inset: 0;
  display: flex; flex-direction: column;
  align-items: center; justify-content: center;
  pointer-events: none;
}
.donut-center-val {
  font-family: var(--cond); font-size: 28px; font-weight: 700; color: var(--text1);
}
.donut-center-lbl {
  font-family: var(--mono); font-size: 9px; color: var(--text3); letter-spacing: 1px;
}
.donut-legend {
  display: flex; flex-wrap: wrap; gap: 10px; justify-content: center;
}
.donut-legend-item {
  display: flex; align-items: center; gap: 6px;
  font-family: var(--mono); font-size: 10px; color: var(--text2);
}
.legend-dot { width: 8px; height: 8px; border-radius: 2px; flex-shrink: 0; }

/* ── REQUEST LOG ── */
.req-log {
  height: 200px; overflow-y: auto;
  font-family: var(--mono); font-size: 11px;
  line-height: 1.8;
  scrollbar-width: thin;
  scrollbar-color: var(--border) transparent;
}
.req-log::-webkit-scrollbar { width: 4px; }
.req-log::-webkit-scrollbar-thumb { background: var(--border); }

.log-entry {
  display: flex; gap: 10px; padding: 2px 0;
  border-bottom: 1px solid rgba(30,48,64,.4);
  animation: fadeIn .3s ease;
}
@keyframes fadeIn { from { opacity: 0; transform: translateX(-6px); } to { opacity:1; transform: none; } }

.log-time   { color: var(--text3); flex-shrink: 0; width: 78px; }
.log-method { color: var(--accent); width: 42px; flex-shrink: 0; font-weight: 600; }
.log-path   { color: var(--text2); flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.log-status { width: 32px; flex-shrink: 0; text-align: right; }
.s2 { color: var(--accent2); }
.s3 { color: var(--warn); }
.s4 { color: var(--accent3); }
.s5 { color: var(--danger); }
.log-dur    { color: var(--text3); width: 56px; flex-shrink: 0; text-align: right; }

/* ── ENDPOINT TABLE ── */
.ep-table { width: 100%; border-collapse: collapse; }
.ep-table th {
  font-family: var(--mono); font-size: 9px; letter-spacing: 2px;
  color: var(--text3); text-align: left; padding: 0 8px 10px;
  text-transform: uppercase; border-bottom: 1px solid var(--border);
}
.ep-table td {
  font-family: var(--mono); font-size: 11px;
  color: var(--text2); padding: 8px; border-bottom: 1px solid rgba(30,48,64,.5);
}
.ep-table td:first-child { color: var(--accent); }
.ep-table tr:hover td { background: var(--bg3); }

.bar-cell { display: flex; align-items: center; gap: 8px; }
.bar-track { flex: 1; height: 4px; background: var(--bg3); border-radius: 2px; }
.bar-fill  { height: 100%; border-radius: 2px; background: linear-gradient(90deg, var(--accent), var(--accent2)); transition: width .6s ease; }

/* ── SYSTEM INFO ── */
.sys-grid {
  display: grid; grid-template-columns: 1fr 1fr;
  gap: 10px; margin-top: 4px;
}
.sys-row {
  display: flex; flex-direction: column; gap: 2px;
  padding: 10px; background: var(--bg2); border-radius: 3px;
}
.sys-key { font-family: var(--mono); font-size: 9px; color: var(--text3); letter-spacing: 1px; text-transform: uppercase; }
.sys-val { font-family: var(--mono); font-size: 12px; color: var(--text1); }

/* ── GAUGE ARC ── */
.gauge-row { display: flex; gap: 16px; align-items: center; margin-top: 8px; }
.gauge-wrap { flex: 1; }
.gauge-label { font-family: var(--mono); font-size: 10px; color: var(--text3); margin-bottom: 4px; letter-spacing: 1px; }
.gauge-track {
  height: 8px; background: var(--bg3); border-radius: 4px; overflow: hidden;
  position: relative;
}
.gauge-fill {
  height: 100%; border-radius: 4px;
  transition: width .8s cubic-bezier(.4,0,.2,1);
}
.gauge-fill.cpu  { background: linear-gradient(90deg, var(--accent), #00b0cc); }
.gauge-fill.mem  { background: linear-gradient(90deg, var(--accent2), #00cc7a); }
.gauge-fill.disk { background: linear-gradient(90deg, var(--warn), var(--accent3)); }
.gauge-pct {
  font-family: var(--cond); font-size: 13px; font-weight: 700;
  color: var(--text1); text-align: right; margin-top: 2px;
}

/* ── STATUS STRIP ── */
.status-strip {
  display: flex; gap: 6px; flex-wrap: wrap; margin-top: 4px;
}
.status-pill {
  display: flex; align-items: center; gap: 6px;
  padding: 4px 10px; border-radius: 2px;
  background: var(--bg2); border: 1px solid var(--border);
  font-family: var(--mono); font-size: 10px; color: var(--text2);
}
.pill-dot { width: 6px; height: 6px; border-radius: 50%; flex-shrink: 0; }
.pill-dot.green { background: var(--accent2); box-shadow: 0 0 8px var(--accent2); }
.pill-dot.amber { background: var(--warn);    box-shadow: 0 0 8px var(--warn); }
.pill-dot.red   { background: var(--danger);  box-shadow: 0 0 8px var(--danger); }

/* ── UPTIME DISPLAY ── */
.uptime-display {
  font-family: var(--mono); font-size: 22px;
  color: var(--accent); letter-spacing: 4px;
  text-align: center; margin: 8px 0;
}

/* ── RESPONSIVE ── */
@media (max-width: 1100px) {
  .grid-top { grid-template-columns: repeat(2,1fr); }
  .grid-mid { grid-template-columns: 1fr; }
  .grid-bot { grid-template-columns: 1fr 1fr; }
}
@media (max-width: 700px) {
  .grid-bot { grid-template-columns: 1fr; }
  .grid-top { grid-template-columns: 1fr 1fr; }
}
</style>
</head>
<body>

<header>
  <div class="logo">
    <div class="logo-icon"></div>
    <div>
      <div class="logo-text">DEVOPS&nbsp;OPS</div>
      <div class="logo-sub">SYSTEM MONITOR — v2.0.0</div>
    </div>
  </div>
  <div class="header-right">
    <div class="live-badge"><div class="live-dot"></div>LIVE</div>
    <div class="header-time" id="hdrTime">--:--:--</div>
  </div>
</header>

<div class="page">

  <!-- KPI CARDS -->
  <div class="grid-top">
    <div class="card">
      <div class="card-label">Requests / sec</div>
      <div class="card-value" id="kpiRps">0<span class="unit">rps</span></div>
      <div class="card-delta" id="kpiRpsDelta">↑ 0 vs last min</div>
      <div class="card-accent-bar" id="kpiRpsBar" style="width:0%;background:var(--accent)"></div>
    </div>
    <div class="card">
      <div class="card-label">Avg Latency</div>
      <div class="card-value" id="kpiLat">0<span class="unit">ms</span></div>
      <div class="card-delta" id="kpiLatDelta">avg over last 60s</div>
      <div class="card-accent-bar" id="kpiLatBar" style="width:0%;background:var(--accent2)"></div>
    </div>
    <div class="card">
      <div class="card-label">CPU Usage</div>
      <div class="card-value" id="kpiCpu">0<span class="unit">%</span></div>
      <div class="card-delta" id="kpiCpuDelta">process cpu</div>
      <div class="card-accent-bar" id="kpiCpuBar" style="width:0%;background:var(--accent3)"></div>
    </div>
    <div class="card">
      <div class="card-label">Memory</div>
      <div class="card-value" id="kpiMem">0<span class="unit">%</span></div>
      <div class="card-delta" id="kpiMemDelta">system ram</div>
      <div class="card-accent-bar" id="kpiMemBar" style="width:0%;background:var(--warn)"></div>
    </div>
  </div>

  <!-- CHARTS ROW -->
  <div class="grid-mid">
    <!-- sparkline area chart -->
    <div class="card">
      <div class="section-title">Throughput &amp; Latency — 60s window</div>
      <div class="chart-wrap">
        <canvas id="chartMain"></canvas>
      </div>
    </div>
    <!-- status donut -->
    <div class="card">
      <div class="section-title">Response Status</div>
      <div class="donut-wrap">
        <div class="donut-canvas-wrap">
          <canvas id="chartDonut"></canvas>
          <div class="donut-center">
            <div class="donut-center-val" id="donutTotal">0</div>
            <div class="donut-center-lbl">REQUESTS</div>
          </div>
        </div>
        <div class="donut-legend">
          <div class="donut-legend-item"><div class="legend-dot" style="background:var(--accent2)"></div><span id="leg2xx">0</span>&nbsp;2xx</div>
          <div class="donut-legend-item"><div class="legend-dot" style="background:var(--warn)"></div><span id="leg4xx">0</span>&nbsp;4xx</div>
          <div class="donut-legend-item"><div class="legend-dot" style="background:var(--danger)"></div><span id="leg5xx">0</span>&nbsp;5xx</div>
        </div>
      </div>
    </div>
  </div>

  <!-- BOTTOM ROW -->
  <div class="grid-bot">
    <!-- Live request log -->
    <div class="card">
      <div class="section-title">Live Request Stream</div>
      <div class="req-log" id="reqLog"></div>
    </div>

    <!-- System resources -->
    <div class="card">
      <div class="section-title">System Resources</div>

      <div style="margin-bottom:14px">
        <div class="gauge-label">CPU</div>
        <div class="gauge-track"><div class="gauge-fill cpu" id="gCpu" style="width:0%"></div></div>
        <div class="gauge-pct" id="gCpuPct">0%</div>
      </div>
      <div style="margin-bottom:14px">
        <div class="gauge-label">MEMORY</div>
        <div class="gauge-track"><div class="gauge-fill mem" id="gMem" style="width:0%"></div></div>
        <div class="gauge-pct" id="gMemPct">0%</div>
      </div>

      <div class="sys-grid" id="sysGrid">
        <div class="sys-row"><div class="sys-key">Uptime</div><div class="sys-val" id="syUptime">—</div></div>
        <div class="sys-row"><div class="sys-key">Platform</div><div class="sys-val" id="syPlatform">—</div></div>
        <div class="sys-row"><div class="sys-key">Node.js</div><div class="sys-val" id="syNode">—</div></div>
        <div class="sys-row"><div class="sys-key">Heap Used</div><div class="sys-val" id="syHeap">—</div></div>
        <div class="sys-row"><div class="sys-key">RSS</div><div class="sys-val" id="syRss">—</div></div>
        <div class="sys-row"><div class="sys-key">Environment</div><div class="sys-val" id="syEnv">—</div></div>
      </div>
    </div>

    <!-- Endpoint hit counts -->
    <div class="card">
      <div class="section-title">Endpoint Activity</div>
      <table class="ep-table" id="epTable">
        <thead><tr>
          <th>Path</th><th>Hits</th><th>Share</th>
        </tr></thead>
        <tbody id="epBody"></tbody>
      </table>

      <div style="margin-top:20px">
        <div class="section-title">Service Health</div>
        <div class="status-strip" id="statusStrip">
          <div class="status-pill"><div class="pill-dot green"></div>HTTP Server</div>
          <div class="status-pill"><div class="pill-dot green"></div>Metrics</div>
          <div class="status-pill" id="pillHealth"><div class="pill-dot green"></div>/health</div>
          <div class="status-pill" id="pillReady"><div class="pill-dot green"></div>/ready</div>
        </div>
      </div>
    </div>
  </div>

</div><!-- /page -->

<script>
//  TINY CANVAS CHART LIBRARY (no dependencies)
function initCanvas(id) {
  const c = document.getElementById(id);
  const dpr = window.devicePixelRatio || 1;
  const rect = c.parentElement.getBoundingClientRect();
  c.width  = rect.width  * dpr;
  c.height = rect.height * dpr;
  c.style.width  = rect.width  + 'px';
  c.style.height = rect.height + 'px';
  const ctx = c.getContext('2d');
  ctx.scale(dpr, dpr);
  return { canvas: c, ctx, w: rect.width, h: rect.height };
}

function drawLine(ctx, data, w, h, color, fill, yMin, yMax) {
  if (data.length < 2) return;
  const range = yMax - yMin || 1;
  const xs = data.map((_, i) => (i / (data.length - 1)) * w);
  const ys = data.map(v => h - ((v - yMin) / range) * h * 0.88 - h * 0.06);

  ctx.beginPath();
  ctx.moveTo(xs[0], ys[0]);
  for (let i = 1; i < data.length; i++) {
    const cpx = (xs[i-1] + xs[i]) / 2;
    ctx.bezierCurveTo(cpx, ys[i-1], cpx, ys[i], xs[i], ys[i]);
  }

  if (fill) {
    ctx.lineTo(xs[xs.length-1], h);
    ctx.lineTo(xs[0], h);
    ctx.closePath();
    const grad = ctx.createLinearGradient(0, 0, 0, h);
    grad.addColorStop(0, fill);
    grad.addColorStop(1, 'transparent');
    ctx.fillStyle = grad;
    ctx.fill();
  }

  ctx.beginPath();
  ctx.moveTo(xs[0], ys[0]);
  for (let i = 1; i < data.length; i++) {
    const cpx = (xs[i-1] + xs[i]) / 2;
    ctx.bezierCurveTo(cpx, ys[i-1], cpx, ys[i], xs[i], ys[i]);
  }
  ctx.strokeStyle = color;
  ctx.lineWidth = 2;
  ctx.stroke();

  // last point glow dot
  const lx = xs[xs.length-1], ly = ys[ys.length-1];
  ctx.beginPath();
  ctx.arc(lx, ly, 4, 0, Math.PI*2);
  ctx.fillStyle = color;
  ctx.fill();
  ctx.beginPath();
  ctx.arc(lx, ly, 8, 0, Math.PI*2);
  ctx.fillStyle = color.replace(')', ',.2)').replace('rgb', 'rgba');
  ctx.fill();
}

function drawGridLines(ctx, w, h, steps=4) {
  ctx.strokeStyle = 'rgba(30,48,64,.6)';
  ctx.lineWidth = 1;
  for (let i = 0; i <= steps; i++) {
    const y = (i / steps) * h;
    ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(w, y); ctx.stroke();
  }
}

//  DONUT CHART
let donutMeta = null;
function initDonut() {
  const c = document.getElementById('chartDonut');
  const sz = 150;
  const dpr = window.devicePixelRatio || 1;
  c.width  = sz * dpr;
  c.height = sz * dpr;
  c.style.width  = sz + 'px';
  c.style.height = sz + 'px';
  const ctx = c.getContext('2d');
  ctx.scale(dpr, dpr);
  donutMeta = { ctx, sz };
}

function drawDonut(s2, s4, s5) {
  if (!donutMeta) return;
  const { ctx, sz } = donutMeta;
  const cx = sz/2, cy = sz/2, r = sz/2-10, ir = sz/2-28;
  const total = s2 + s4 + s5 || 1;
  ctx.clearRect(0, 0, sz, sz);

  const segments = [
    { val: s2, color: '#00ff9d' },
    { val: s4, color: '#ffd600' },
    { val: s5, color: '#ff1744' },
  ].filter(s => s.val > 0);

  if (segments.length === 0) {
    // empty ring
    ctx.beginPath();
    ctx.arc(cx, cy, r, 0, Math.PI*2);
    ctx.arc(cx, cy, ir, 0, Math.PI*2, true);
    ctx.fillStyle = 'rgba(30,48,64,.5)';
    ctx.fill();
    return;
  }

  let startAngle = -Math.PI / 2;
  for (const seg of segments) {
    const sweep = (seg.val / total) * Math.PI * 2;
    ctx.beginPath();
    ctx.arc(cx, cy, r, startAngle, startAngle + sweep);
    ctx.arc(cx, cy, ir, startAngle + sweep, startAngle, true);
    ctx.closePath();
    ctx.fillStyle = seg.color;
    ctx.fill();
    startAngle += sweep;
  }

  // center hole bg
  ctx.beginPath();
  ctx.arc(cx, cy, ir - 2, 0, Math.PI*2);
  ctx.fillStyle = '#0d1117';
  ctx.fill();
}

//  MAIN CHART
let mainMeta = null;
function initMain() {
  mainMeta = initCanvas('chartMain');
}

function drawMain(rpsData, latData) {
  if (!mainMeta) return;
  const { ctx, w, h } = mainMeta;
  ctx.clearRect(0, 0, w, h);
  drawGridLines(ctx, w, h);

  const maxRps = Math.max(...rpsData, 1);
  const maxLat = Math.max(...latData, 1);

  drawLine(ctx, rpsData, w, h, '#00e5ff', 'rgba(0,229,255,.08)', 0, maxRps);
  drawLine(ctx, latData, w, h, '#00ff9d', 'rgba(0,255,157,.05)', 0, maxLat);

  // Y-axis labels
  ctx.font = '9px Share Tech Mono';
  ctx.fillStyle = 'rgba(122,155,176,.6)';
  ctx.fillText('RPS', 4, 12);
  ctx.fillStyle = 'rgba(0,255,157,.6)';
  ctx.fillText('LAT', w - 28, 12);
}

//  ENDPOINT TABLE
const epCounts = {};
let totalReqs = 0;

function updateEpTable() {
  const sorted = Object.entries(epCounts).sort((a,b) => b[1]-a[1]).slice(0, 6);
  const max = sorted[0]?.[1] || 1;
  const tbody = document.getElementById('epBody');
  tbody.innerHTML = '';
  for (const [path, count] of sorted) {
    const pct = Math.round((count/max)*100);
    const row = document.createElement('tr');
    row.innerHTML = \`
      <td>\${path}</td>
      <td>\${count}</td>
      <td>
        <div class="bar-cell">
          <div class="bar-track"><div class="bar-fill" style="width:\${pct}%"></div></div>
          <span style="font-size:10px;color:var(--text3);flex-shrink:0">\${Math.round((count/totalReqs)*100)||0}%</span>
        </div>
      </td>\`;
    tbody.appendChild(row);
  }
}

//  REQUEST LOG
const logEl = document.getElementById('reqLog');
const LOG_MAX = 80;
let logCount = 0;

function appendLog(ts, method, path, status, dur) {
  const d = new Date(ts);
  const t = d.toTimeString().slice(0,8);
  const sc = status >= 500 ? 's5' : status >= 400 ? 's4' : status >= 300 ? 's3' : 's2';
  const entry = document.createElement('div');
  entry.className = 'log-entry';
  entry.innerHTML = \`
    <span class="log-time">\${t}</span>
    <span class="log-method">\${method}</span>
    <span class="log-path">\${path}</span>
    <span class="log-status \${sc}">\${status}</span>
    <span class="log-dur">\${Math.round(dur)}ms</span>
  \`;
  logEl.prepend(entry);
  logCount++;
  if (logCount > LOG_MAX) {
    logEl.lastChild && logEl.removeChild(logEl.lastChild);
  }
}

//  SSE  (Server-Sent Events)
const evtSrc = new EventSource('/api/stream');

evtSrc.addEventListener('tick', e => {
  const d = JSON.parse(e.data);

  // KPI cards
  const rps = d.rps[d.rps.length-1] ?? 0;
  const lat = d.p99[d.p99.length-1] ?? 0;
  const cpu = d.cpu[d.cpu.length-1] ?? 0;
  const mem = d.mem[d.mem.length-1] ?? 0;

  document.getElementById('kpiRps').innerHTML = rps + '<span class="unit">rps</span>';
  document.getElementById('kpiLat').innerHTML = lat + '<span class="unit">ms</span>';
  document.getElementById('kpiCpu').innerHTML = cpu + '<span class="unit">%</span>';
  document.getElementById('kpiMem').innerHTML = mem + '<span class="unit">%</span>';

  document.getElementById('kpiRpsBar').style.width = Math.min(rps * 5, 100) + '%';
  document.getElementById('kpiLatBar').style.width = Math.min(lat / 2, 100) + '%';
  document.getElementById('kpiCpuBar').style.width = cpu + '%';
  document.getElementById('kpiMemBar').style.width = mem + '%';

  // gauges
  document.getElementById('gCpu').style.width = cpu + '%';
  document.getElementById('gCpuPct').textContent = cpu + '%';
  document.getElementById('gMem').style.width = mem + '%';
  document.getElementById('gMemPct').textContent = mem + '%';

  // donut
  const sc = d.statusCounts;
  const tot2 = sc.reduce((a,b) => a + (b['2xx']||0), 0);
  const tot4 = sc.reduce((a,b) => a + (b['4xx']||0), 0);
  const tot5 = sc.reduce((a,b) => a + (b['5xx']||0), 0);
  const totAll = tot2 + tot4 + tot5;
  document.getElementById('donutTotal').textContent = totAll;
  document.getElementById('leg2xx').textContent = tot2;
  document.getElementById('leg4xx').textContent = tot4;
  document.getElementById('leg5xx').textContent = tot5;
  drawDonut(tot2, tot4, tot5);

  // main chart
  drawMain(d.rps, d.p99);

  // system info
  const si = d.sysInfo;
  document.getElementById('syUptime').textContent   = si.uptime;
  document.getElementById('syPlatform').textContent = si.platform;
  document.getElementById('syNode').textContent     = si.nodeVersion;
  document.getElementById('syHeap').textContent     = si.heapUsed;
  document.getElementById('syRss').textContent      = si.rss;
  document.getElementById('syEnv').textContent      = si.env;
});

evtSrc.addEventListener('request', e => {
  const d = JSON.parse(e.data);
  appendLog(d.ts, d.method, d.path, d.status, d.duration);

  // endpoint tracking
  const key = d.method + ' ' + d.path;
  epCounts[key] = (epCounts[key] || 0) + 1;
  totalReqs++;
  updateEpTable();
});

//  CLOCK
function tickClock() {
  document.getElementById('hdrTime').textContent = new Date().toTimeString().slice(0,8);
}
setInterval(tickClock, 1000);
tickClock();

//  INIT
initDonut();
initMain();
drawDonut(0,0,0);
</script>
</body>
</html>`;

//  SSE  (Server-Sent Events — live data stream)
const sseClients = new Set();

// Broadcast every tick
setInterval(() => {
  if (sseClients.size === 0) return;

  const mem = process.memoryUsage();

  const payload = JSON.stringify({
    rps:          ring.rps,
    p99:          ring.p99,
    cpu:          ring.cpu,
    mem:          ring.memPct,
    statusCounts: ring.statusCounts,
    sysInfo: {
      uptime:      fmtDuration(process.uptime()),
      platform:    `${process.platform}/${process.arch}`,
      nodeVersion: process.version,
      heapUsed:    fmtBytes(mem.heapUsed),
      rss:         fmtBytes(mem.rss),
      env:         process.env.NODE_ENV || 'development',
    },
  });

  const msg = `event: tick\ndata: ${payload}\n\n`;
  for (const res of sseClients) {
    try { res.write(msg); } catch { sseClients.delete(res); }
  }
}, 1000);

// Utility formatters
function fmtBytes(b) {
  if (b < 1024)       return b + ' B';
  if (b < 1048576)    return (b / 1024).toFixed(1) + ' KB';
  if (b < 1073741824) return (b / 1048576).toFixed(1) + ' MB';
  return (b / 1073741824).toFixed(2) + ' GB';
}

function fmtDuration(sec) {
  const d = Math.floor(sec / 86400);
  const h = Math.floor((sec % 86400) / 3600);
  const m = Math.floor((sec % 3600) / 60);
  const s = Math.floor(sec % 60);
  if (d > 0) return `${d}d ${h}h ${m}m`;
  if (h > 0) return `${h}h ${m}m ${s}s`;
  return `${m}m ${s}s`;
}

//  ROUTES

// Dashboard
app.get('/', (req, res) => {
  res.setHeader('Content-Type', 'text/html');
  res.send(DASHBOARD_HTML);
});

// SSE endpoint
app.get('/api/stream', (req, res) => {
  res.setHeader('Content-Type',  'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection',    'keep-alive');
  res.setHeader('X-Accel-Buffering', 'no');
  res.flushHeaders();
  res.write(': connected\n\n');
  sseClients.add(res);

  // Emit request events via closure (attached to this SSE connection)
  res._isSseConn = true;

  req.on('close', () => { sseClients.delete(res); });
});

// Broadcast request event to all SSE clients
function broadcastRequest(method, urlPath, status, duration) {
  if (sseClients.size === 0) return;
  const payload = JSON.stringify({
    ts:       Date.now(),
    method,
    path:     urlPath,
    status,
    duration: duration * 1000,
  });
  const msg = `event: request\ndata: ${payload}\n\n`;
  for (const res of sseClients) {
    try { res.write(msg); } catch { sseClients.delete(res); }
  }
}

// Hook into the existing middleware to also broadcast requests
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    if (req.path === '/api/stream' || req.path === '/metrics') return;
    broadcastRequest(req.method, req.path, res.statusCode, (Date.now() - start) / 1000);
  });
  next();
});

// Health check
app.get('/health', (req, res) => {
  res.status(200).json({
    status:    'healthy',
    timestamp: new Date().toISOString(),
    uptime:    process.uptime(),
  });
});

// Readiness
app.get('/ready', (req, res) => {
  res.status(200).json({
    status:    'ready',
    timestamp: new Date().toISOString(),
  });
});

// Prometheus metrics
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// API status (richer)
app.get('/api/status', (req, res) => {
  const mem = process.memoryUsage();
  res.json({
    status:    'ok',
    uptime:    process.uptime(),
    uptimeFmt: fmtDuration(process.uptime()),
    memory: {
      heapUsed:  fmtBytes(mem.heapUsed),
      heapTotal: fmtBytes(mem.heapTotal),
      rss:       fmtBytes(mem.rss),
      external:  fmtBytes(mem.external),
    },
    cpu:       process.cpuUsage(),
    platform:  process.platform,
    arch:      process.arch,
    nodeVersion: process.version,
    env:       process.env.NODE_ENV || 'development',
    ring: {
      rps: ring.rps.slice(-5),
      p99: ring.p99.slice(-5),
      cpu: ring.cpu.slice(-5),
      mem: ring.memPct.slice(-5),
    },
  });
});

// Slow endpoint (latency testing)
app.get('/api/slow', async (req, res) => {
  const delay = Math.random() * 2000;
  await new Promise(resolve => setTimeout(resolve, delay));
  res.json({ message: 'Slow endpoint', delay: `${delay.toFixed(0)}ms` });
});

// Echo POST
app.post('/api/data', (req, res) => {
  res.status(201).json({
    message:   'Data received',
    data:      req.body,
    timestamp: new Date().toISOString(),
  });
});

// Error injection (for testing)
app.get('/api/error', (req, res) => {
  res.status(500).json({ error: 'Intentional error for testing' });
});

// 404 JSON
app.use((req, res) => {
  res.status(404).json({ error: 'Not Found', path: req.path });
});

// Error handler
app.use((err, req, res, _next) => {
  console.error('Error:', err);
  res.status(500).json({ error: 'Internal Server Error', message: err.message });
});

//  SERVER STARTUP
server.listen(PORT, '0.0.0.0', () => {
  console.log('='.repeat(70));
  console.log('🚀  DevOps Application v2.0.0');
  console.log('='.repeat(70));
  console.log(`📍  Server   : http://0.0.0.0:${PORT}`);
  console.log(`📊  Dashboard: http://0.0.0.0:${PORT}/`);
  console.log(`🏥  Health   : http://0.0.0.0:${PORT}/health`);
  console.log(`📈  Metrics  : http://0.0.0.0:${PORT}/metrics`);
  console.log(`🌐  Env      : ${process.env.NODE_ENV || 'development'}`);
  console.log('='.repeat(70));
});

// Graceful shutdown
const shutdown = (signal) => {
  console.log(`\n${signal} received — graceful shutdown…`);
  server.close(() => {
    console.log('✅ HTTP server closed');
    process.exit(0);
  });
  setTimeout(() => { console.error('⚠️  Forced shutdown'); process.exit(1); }, 10000);
};

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT',  () => shutdown('SIGINT'));

module.exports = app;