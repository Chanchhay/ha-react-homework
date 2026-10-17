import { useEffect, useMemo, useRef, useState } from 'react';

const SAMPLE_INTERVAL = 3000;
const SAMPLE_LIMIT = 60;
const name = (value) => value || '—';
const time = (date) => new Date(date).toLocaleTimeString();

function ServiceCard({ label, value, subtitle, accent = false }) {
  return (
    <div className={`stat-card ${accent ? 'accent' : ''}`}>
      <div className="eyebrow">{label}</div>
      <div className="stat-value">{value}</div>
      {subtitle && <div className="stat-subtitle">{subtitle}</div>}
    </div>
  );
}

function FlowNode({ label, value, detail, selected = false }) {
  return (
    <div className={`flow-node ${selected ? 'selected' : ''}`}>
      <span className="eyebrow">{label}</span>
      <strong>{value}</strong>
      <span className="node-detail">{detail}</span>
    </div>
  );
}

function App() {
  const [samples, setSamples] = useState([]);
  const [events, setEvents] = useState([]);
  const [status, setStatus] = useState('checking');
  const [lastError, setLastError] = useState('');
  const [autoRefresh, setAutoRefresh] = useState(true);
  const [refreshKey, setRefreshKey] = useState(0);
  const previousBalancer = useRef(null);

  useEffect(() => {
    let canceled = false;
    let pending = false;
    let controller;

    const sample = async () => {
      if (pending) return;
      pending = true;
      controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 2500);
      const startedAt = performance.now();

      try {
        const response = await fetch(`/api/trace?sample=${Date.now()}`, {
          cache: 'no-store',
          signal: controller.signal,
        });
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        const data = await response.json();
        if (canceled) return;

        // This header is set by the actual HAProxy that returned the response.
        // It is absent when accessing a web server directly.
        const lb = response.headers.get('X-Load-Balancer') || 'DIRECT';
        const next = {
          id: data.requestId,
          at: new Date().toISOString(),
          lb,
          backend: data.backend,
          backendIp: data.backendIp,
          hostname: data.machineHostname,
          serverTime: data.serverTime,
          uptime: data.appUptimeSeconds,
          ms: Math.round(performance.now() - startedAt),
          ok: true,
        };

        if (previousBalancer.current && previousBalancer.current !== lb) {
          setEvents((previous) => [{
            id: data.requestId,
            at: next.at,
            text: `Observed load balancer changed: ${previousBalancer.current} → ${lb}`,
          }, ...previous].slice(0, 12));
        }
        previousBalancer.current = lb;
        setStatus('connected');
        setLastError('');
        setSamples((previous) => [next, ...previous].slice(0, SAMPLE_LIMIT));
      } catch (error) {
        if (canceled) return;
        setStatus('unreachable');
        setLastError(error.name === 'AbortError' ? 'Request timed out' : error.message);
        setSamples((previous) => [{
          id: `error-${Date.now()}`,
          at: new Date().toISOString(),
          lb: '—',
          backend: '—',
          ms: Math.round(performance.now() - startedAt),
          ok: false,
        }, ...previous].slice(0, SAMPLE_LIMIT));
      } finally {
        clearTimeout(timeout);
        pending = false;
      }
    };

    sample();
    const interval = autoRefresh ? setInterval(sample, SAMPLE_INTERVAL) : null;
    return () => {
      canceled = true;
      controller?.abort();
      clearInterval(interval);
    };
  }, [autoRefresh, refreshKey]);

  const latest = samples.find((s) => s.ok);
  const successful = useMemo(() => samples.filter((s) => s.ok), [samples]);
  const web01 = successful.filter((s) => s.backend === 'WEB-01').length;
  const web02 = successful.filter((s) => s.backend === 'WEB-02').length;
  const total = web01 + web02;
  const percentage = (count) => total ? Math.round((count / total) * 100) : 0;
  const observedLB = latest?.lb || '—';
  const observedBackend = latest?.backend || '—';
  const elapsed = latest?.ms ?? '—';
  const isReady = status === 'connected';

  return (
    <main className="page">
      <header className="header">
        <div className="brand">
          <div className="brand-mark"><span>HA</span></div>
          <div>
            <div className="brand-name">Infrastructure Monitor</div>
            <div className="brand-subtitle">React · HAProxy · Keepalived · Vagrant</div>
          </div>
        </div>
        <div className={`status-pill ${status}`}>
          <span className="status-dot" />
          {status === 'connected' ? 'VIP endpoint reachable' : status === 'checking' ? 'Checking route…' : 'Latest request failed'}
        </div>
      </header>

      <section className="hero">
        <div>
          <div className="section-label">LIVE NETWORK OBSERVABILITY</div>
          <h1>See where every diagnostic request goes.</h1>
          <p>Trace actual HTTP requests through your active load balancer to one of your React web servers. Observe routing changes during failure testing.</p>
        </div>
        <div className="action-bar">
          <label className="toggle">
            <input type="checkbox" checked={autoRefresh} onChange={(event) => setAutoRefresh(event.target.checked)} />
            <span>Auto-sample every 3s</span>
          </label>
          <button type="button" onClick={() => setRefreshKey((n) => n + 1)}>Send test request ↗</button>
        </div>
      </section>

      {lastError && <div className="notice danger">Latest request failed: {lastError}. This does not by itself identify which VM failed; it may be a temporary failover interruption.</div>}

      <section className="stat-grid" aria-label="Latest observed request">
        <ServiceCard label="Browser entry point" value={window.location.host} subtitle="Address used to open this dashboard" />
        <ServiceCard label="Responding load balancer" value={observedLB} subtitle={observedLB === 'DIRECT' ? 'No HAProxy response header' : 'Latest successful request'} accent />
        <ServiceCard label="Responding backend" value={observedBackend} subtitle={latest?.backendIp || 'Awaiting a response'} />
        <ServiceCard label="Browser round trip" value={`${elapsed}${typeof elapsed === 'number' ? ' ms' : ''}`} subtitle="Last successful API sample" />
      </section>

      <section className="panel flow-panel">
        <div className="panel-heading">
          <div><h2>Latest observed request path</h2><p>Identity data is provided by HAProxy and the serving Node.js process.</p></div>
          <div className="mini-label">{latest ? `Sampled at ${time(latest.at)}` : 'No samples yet'}</div>
        </div>
        <div className="flow">
          <FlowNode label="Client" value="Browser" detail="GET /api/trace" />
          <span className="flow-arrow">→</span>
          <FlowNode label="HAProxy" value={observedLB} detail={observedLB === 'DIRECT' ? 'Bypassed' : 'Response identity'} selected />
          <span className="flow-arrow">→</span>
          <FlowNode label="React HTTP server" value={observedBackend} detail={latest?.backendIp || 'Not sampled'} />
        </div>
        <div className="info-line">The HTML, CSS, JavaScript and API requests can be served by different backend instances. This diagram describes the latest <code>/api/trace</code> request only.</div>
      </section>

      <div className="columns">
        <section className="panel">
          <div className="panel-heading"><div><h2>Observed backend distribution</h2><p>Counts from up to the last {SAMPLE_LIMIT} browser samples; not global server traffic.</p></div></div>
          <div className="distribution">
            <div className="distribution-top"><span>WEB-01</span><span>{web01} requests · {percentage(web01)}%</span></div>
            <div className="bar"><div className="bar-fill turquoise" style={{ width: `${percentage(web01)}%` }} /></div>
            <div className="distribution-top"><span>WEB-02</span><span>{web02} requests · {percentage(web02)}%</span></div>
            <div className="bar"><div className="bar-fill blue" style={{ width: `${percentage(web02)}%` }} /></div>
          </div>
          <div className="hint">With round-robin and two healthy backends, sequential HTTP requests should usually alternate. Browser polling is only a sampling method.</div>
        </section>

        <section className="panel">
          <div className="panel-heading"><div><h2>Routing events</h2><p>Recorded when this browser observes a different load balancer.</p></div></div>
          <div className="event-list">
            {events.length === 0 ? <div className="empty">No load-balancer changes observed yet. Stop LB-01 after enabling Keepalived to test failover.</div> : events.map((event) => (
              <div className="event" key={event.id}><span className="event-dot" /><div><div>{event.text}</div><small>{time(event.at)}</small></div></div>
            ))}
          </div>
          <div className="hint">An observed change suggests a routing transition; Keepalived logs are needed to confirm the actual failover cause.</div>
        </section>
      </div>

      <section className="panel">
        <div className="panel-heading"><div><h2>Recent requests</h2><p>Live diagnostic history in this browser session.</p></div><span className="mini-label">{successful.length} successful samples</span></div>
        <div className="table-wrapper">
          <table>
            <thead><tr><th>Time</th><th>Load balancer</th><th>Backend</th><th>Latency</th><th>Result</th><th>Request ID</th></tr></thead>
            <tbody>
              {samples.length === 0 ? <tr><td colSpan="6" className="empty">Waiting for first request…</td></tr> : samples.slice(0, 14).map((sample) => (
                <tr key={sample.id}>
                  <td>{time(sample.at)}</td><td>{sample.lb}</td><td>{sample.backend}</td>
                  <td>{sample.ms} ms</td>
                  <td><span className={`tag ${sample.ok ? 'ok' : 'bad'}`}>{sample.ok ? 'OK' : 'FAILED'}</span></td>
                  <td className="mono">{sample.ok ? sample.id.slice(0, 8) : '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <section className="footer-info">
        <div><strong>Endpoint:</strong> <code>/api/trace</code> · <strong>HAProxy health check:</strong> <code>/health</code></div>
        <div>{latest ? `Backend host: ${name(latest.hostname)} · App process uptime: ${Math.floor(latest.uptime / 60)} minutes` : 'Collecting data…'}</div>
        <div className="footer-note">To show the real health of both backends or the actual VIP owner, add a secured management API that reads HAProxy status and Keepalived state. This demo does not infer them from a single successful request.</div>
      </section>
    </main>
  );
}

export default App;
