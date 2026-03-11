# Al-Mudeer Library - Incident Response Runbook

## Overview

This runbook provides step-by-step procedures for responding to common library-related incidents.

**On-Call Contact:** See PagerDuty rotation
**Escalation Path:** On-Call → Team Lead → VP Engineering
**Status Page:** status.almudeer.com

---

## Table of Contents

1. [Storage Quota Emergency](#storage-quota-emergency)
2. [High Error Rate](#high-error-rate)
3. [Upload Failures](#upload-failures)
4. [High Latency](#high-latency)
5. [Share Notification Failures](#share-notification-failures)
6. [Service Outage](#service-outage)
7. [Data Corruption](#data-corruption)

---

## Storage Quota Emergency

**Alert:** `LibraryStorageQuotaEmergency` - License at 95% capacity

### Severity: HIGH
### Impact: Users cannot upload new files

### Diagnosis Steps

1. **Identify affected license:**
   ```bash
   curl -s http://localhost:8000/metrics | grep library_quota_warning | grep "= 3"
   ```

2. **Check storage breakdown:**
   ```bash
   curl -X GET "http://localhost:8000/api/library/usage/statistics" \
     -H "X-License-Key: <LICENSE_KEY>"
   ```

3. **Identify largest items:**
   ```sql
   SELECT id, title, type, file_size, created_at 
   FROM library_items 
   WHERE license_key_id = <LICENSE_ID> 
   AND deleted_at IS NULL 
   ORDER BY file_size DESC 
   LIMIT 20;
   ```

### Resolution Steps

1. **Contact customer** (if external):
   - Notify about storage limit
   - Offer cleanup assistance
   - Discuss upgrade options

2. **Temporary relief options:**
   ```sql
   -- Identify items in trash (can be permanently deleted)
   SELECT COUNT(*), SUM(file_size) 
   FROM library_items 
   WHERE license_key_id = <LICENSE_ID> 
   AND deleted_at IS NOT NULL;
   
   -- Permanently delete trash older than 30 days
   DELETE FROM library_items 
   WHERE license_key_id = <LICENSE_ID> 
   AND deleted_at < datetime('now', '-30 days');
   ```

3. **Increase quota** (if appropriate):
   - Update `MAX_STORAGE_PER_LICENSE` environment variable
   - Or add license-specific override

4. **Post-incident:**
   - [ ] Review quota policies
   - [ ] Implement proactive warnings at 70%
   - [ ] Update customer documentation

---

## High Error Rate

**Alert:** `LibraryHighErrorRate` - Error rate > 0.1/sec

### Severity: MEDIUM
### Impact: Degraded user experience

### Diagnosis Steps

1. **Check error breakdown:**
   ```bash
   curl -s http://localhost:8000/metrics | grep library_errors_total
   ```

2. **Review recent logs:**
   ```bash
   journalctl -u almudeer -n 100 --no-pager | grep -i "library.*error"
   ```

3. **Check dependent services:**
   ```bash
   # Redis health
   redis-cli ping
   
   # Database health
   python -c "from db_helper import get_db; import asyncio; asyncio.run(get_db().__aenter__())"
   
   # File storage
   ls -la /path/to/uploads
   ```

### Resolution Steps

1. **Identify error type:**
   - `STORAGE_LIMIT_EXCEEDED`: See Storage Quota section
   - `FILE_TOO_LARGE`: Check file size limits
   - `INVALID_FILE_TYPE`: Review MIME type validation
   - `DATABASE_ERROR`: Check database connectivity

2. **Apply fix based on error type**

3. **Monitor recovery:**
   ```bash
   watch -n 5 'curl -s http://localhost:8000/metrics | grep library_errors_total'
   ```

---

## Upload Failures

**Alert:** `LibraryUploadFailures` - Upload failure rate > 0.05/sec

### Severity: MEDIUM
### Impact: Users cannot upload files

### Diagnosis Steps

1. **Check failure reasons:**
   ```bash
   curl -s http://localhost:8000/metrics | grep -E "library_uploads_total.*failed"
   ```

2. **Test upload manually:**
   ```bash
   echo "test content" > /tmp/test.txt
   curl -X POST "http://localhost:8000/api/library/upload" \
     -H "X-License-Key: <TEST_KEY>" \
     -F "file=@/tmp/test.txt" \
     -v
   ```

3. **Check file storage service:**
   ```bash
   df -h /path/to/uploads
   ls -la /path/to/uploads/library/
   ```

### Resolution Steps

1. **If disk full:**
   ```bash
   # Clean up old files
   find /path/to/uploads/library -mtime +90 -delete
   
   # Or expand storage
   ```

2. **If permission issues:**
   ```bash
   chown -R almudeer:almudeer /path/to/uploads
   chmod -R 755 /path/to/uploads
   ```

3. **If python-magic issues:**
   ```bash
   # Reinstall libmagic
   apt-get update && apt-get install -y libmagic1
   pip install --force-reinstall python-magic
   ```

---

## High Latency

**Alert:** `LibraryHighLatency` - p95 latency > 1s

### Severity: MEDIUM
### Impact: Slow user experience

### Diagnosis Steps

1. **Check operation-specific latency:**
   ```bash
   curl -s http://localhost:8000/metrics | grep library_operation_duration
   ```

2. **Check database slow queries:**
   ```sql
   -- SQLite: Check for locks
   SELECT * FROM pragma_lock_status;
   
   -- PostgreSQL: Check slow queries
   SELECT query, calls, mean_time 
   FROM pg_stat_statements 
   WHERE query LIKE '%library_items%' 
   ORDER BY mean_time DESC 
   LIMIT 10;
   ```

3. **Check system resources:**
   ```bash
   top -p $(pgrep -f almudeer)
   iostat -x 1 5
   ```

### Resolution Steps

1. **If database locks:**
   - Identify long-running transactions
   - Consider killing blocking queries
   - Optimize problematic queries

2. **If CPU bound:**
   - Scale horizontally
   - Enable caching
   - Optimize hot paths

3. **If I/O bound:**
   - Check disk health
   - Consider SSD upgrade
   - Implement read replicas

---

## Share Notification Failures

**Alert:** `LibraryShareNotificationFailures`

### Severity: LOW
### Impact: Users don't receive share notifications

### Diagnosis Steps

1. **Check notification queue:**
   ```bash
   redis-cli LLEN notifications:queue
   ```

2. **Check WebSocket connections:**
   ```bash
   curl -s http://localhost:8000/metrics | grep websocket
   ```

3. **Review notification logs:**
   ```bash
   grep "share.*notification" /var/log/almudeer/*.log
   ```

### Resolution Steps

1. **Clear stuck queue:**
   ```bash
   redis-cli DEL notifications:queue
   ```

2. **Restart notification worker:**
   ```bash
   systemctl restart almudeer-workers
   ```

3. **Verify WebSocket connectivity:**
   - Check firewall rules
   - Verify reverse proxy configuration

---

## Service Outage

**Alert:** `LibraryEndpointDown` - Backend unreachable

### Severity: CRITICAL
### Impact: Complete service unavailability

### Diagnosis Steps

1. **Check service status:**
   ```bash
   systemctl status almudeer
   docker ps | grep almudeer
   ```

2. **Check logs:**
   ```bash
   journalctl -u almudeer -n 200 --no-pager
   ```

3. **Check dependencies:**
   ```bash
   # Database
   pg_isready -h localhost -p 5432
   
   # Redis
   redis-cli ping
   ```

### Resolution Steps

1. **Attempt restart:**
   ```bash
   systemctl restart almudeer
   # or
   docker restart almudeer
   ```

2. **If restart fails:**
   - Check disk space
   - Check memory
   - Review recent deployments

3. **Rollback if needed:**
   ```bash
   # Railway
   railway rollback
   
   # Docker
   docker pull almudeer:previous-tag
   docker restart almudeer
   ```

4. **Post-incident:**
   - [ ] Conduct blameless postmortem
   - [ ] Update runbook
   - [ ] Implement preventive measures

---

## Data Corruption

**Severity:** CRITICAL
**Impact:** Potential data loss

### Diagnosis Steps

1. **Verify corruption:**
   ```sql
   -- Check for inconsistent data
   SELECT COUNT(*) FROM library_items WHERE id IS NULL;
   SELECT * FROM library_items WHERE file_size < 0;
   ```

2. **Check backup integrity:**
   ```bash
   ls -la /backups/library/
   ```

### Resolution Steps

1. **Stop writes immediately:**
   ```bash
   # Enable maintenance mode
   curl -X POST http://localhost:8000/api/admin/maintenance/enable
   ```

2. **Restore from backup:**
   ```bash
   # Restore database
   sqlite3 almudeer.db < /backups/library/latest.sql
   
   # Or restore files
   rsync -av /backups/library/files/ /path/to/uploads/library/
   ```

3. **Verify restoration:**
   ```sql
   SELECT COUNT(*) FROM library_items;
   ```

4. **Resume operations:**
   ```bash
   curl -X POST http://localhost:8000/api/admin/maintenance/disable
   ```

---

## Escalation Contacts

| Role | Contact | Availability |
|------|---------|--------------|
| On-Call Engineer | PagerDuty | 24/7 |
| Team Lead | Slack: @team-lead | Business hours |
| VP Engineering | Slack: @vp-eng | Emergency only |
| Database Admin | Email: dba@almudeer.com | Business hours |

---

## Post-Incident Checklist

- [ ] Incident documented in incident log
- [ ] Postmortem scheduled (for P0/P1 incidents)
- [ ] Runbook updated if needed
- [ ] Monitoring improved if gaps identified
- [ ] Customer communication sent (if applicable)
- [ ] Follow-up tasks created and assigned

---

**Last Updated:** 2026-03-11
**Version:** 1.0
