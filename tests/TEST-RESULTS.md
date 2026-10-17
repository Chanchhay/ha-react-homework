# Task 6 — Failure simulation evidence

Record **actual observed results** here. Do not mark a test PASS unless you performed it. Keep screenshots under `screenshots/` in your repository.

| # | Scenario | Command / action | Expected | Observed result | Pass/Fail | Evidence |
|---|----------|------------------|----------|-----------------|-----------|----------|
| 1 | Stop React on WEB-01 | `vagrant ssh web-01 -c 'sudo systemctl stop react-app'` | VIP requests continue via WEB-02 | TODO | TODO | TODO |
| 2 | Restart WEB-01 | `vagrant ssh web-01 -c 'sudo systemctl start react-app'` | WEB-01 rejoins backend pool | TODO | TODO | TODO |
| 3 | Stop HAProxy on LB-01 | `vagrant ssh lb-01 -c 'sudo systemctl stop haproxy'` | VIP transfers to LB-02 | TODO | TODO | TODO |
| 4 | Shut down LB-01 | `vagrant halt lb-01` | VIP remains reachable through LB-02 | TODO | TODO | TODO |
| 5 | Recover LB-01 | `vagrant up lb-01` | VIP follows configured preemption policy | TODO | TODO | TODO |
| 6 | Reboot WEB-01 | `vagrant reload web-01` | react-app automatically returns to active | TODO | TODO | TODO |

**Run tests separately and restore healthy services between scenarios.** In particular, after Test 3 restart HAProxy on LB-01 before beginning Test 4; otherwise, LB-01 may remain in Keepalived's FAULT state after reboot. Wait for the VIP to settle, then recheck its owner.

For each scenario, capture:

- Before: `curl -i http://192.168.56.100/api/trace`, `ip -4 addr show eth1` on the current master.
- After: the same request and interface commands on both load balancers.
- Logs: `sudo journalctl -u haproxy -n 40 --no-pager` and/or `sudo journalctl -u keepalived -n 40 --no-pager`.
- Screenshots: actual dashboard response showing `LB-01`/`LB-02`, `WEB-01`/`WEB-02` as appropriate.

Restore services after experiments:

```bash
vagrant up lb-01
vagrant ssh lb-01 -c 'sudo systemctl start haproxy keepalived'
vagrant ssh web-01 -c 'sudo systemctl start react-app'
```

Use `bash scripts/check-health.sh --all` to verify the environment after recovery. The health checker verifies HTTP 200 responses; it does not independently prove correct VRRP ownership. For that, inspect `ip -4 addr show eth1` on both load balancers.
