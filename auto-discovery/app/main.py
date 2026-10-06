"""
EC2 Auto-Discovery Agent v4 — Zero Touch
─────────────────────────────────────────
Every 30 seconds (state) / 2 minutes (CloudWatch metrics):
  1. Calls AWS EC2 API directly — INSTANT state (running/stopped)
  2. Exposes ec2_instance_state gauge on /metrics endpoint
  3. Prometheus scrapes /metrics every 30s → dashboard updates in <30s
  4. CloudWatch metrics (CPU/Network) collected every 2 min separately

State detection is INSTANT via EC2 API — no CloudWatch delay.
New/stopped instances appear in dashboard within 30 seconds.

API:
  GET  /health    - status + next scan
  GET  /status    - last collection result
  GET  /instances - all discovered instances
  POST /collect   - trigger immediate collection
  GET  /debug     - AWS connectivity test
"""

import asyncio
import logging
import os
from datetime import datetime, timezone, timedelta

import boto3
import uvicorn
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.interval import IntervalTrigger
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from prometheus_client import Counter, Gauge, Info, generate_latest, CONTENT_TYPE_LATEST
from starlette.responses import Response

from .aws_collector import collect_and_write

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s — %(message)s"
)
logger = logging.getLogger(__name__)

INTERVAL        = int(os.getenv("DISCOVERY_INTERVAL_MINUTES", "2"))
STATE_INTERVAL  = int(os.getenv("STATE_INTERVAL_SECONDS", "30"))
PROM_DIR        = os.getenv("PROM_TEXTFILE_DIR", "/prometheus_textfiles")
REGIONS         = [r.strip() for r in os.getenv("AWS_REGIONS", "us-east-1").split(",") if r.strip()]
TAG_FILTER_KEY  = os.getenv("TAG_FILTER_KEY", "")
TAG_FILTER_VAL  = os.getenv("TAG_FILTER_VALUE", "true")

# ── Self metrics ────────────────────────────────────────────────────
runs_total    = Counter("autodiscovery_runs_total",          "Total collection runs")
errors_total  = Counter("autodiscovery_errors_total",        "Collection errors")
instances_g   = Gauge("autodiscovery_instances_total",       "Total EC2 instances")
running_g     = Gauge("autodiscovery_instances_running",     "Running EC2 instances")
duration_g    = Gauge("autodiscovery_duration_seconds",      "Last collection duration")
last_run_g    = Gauge("autodiscovery_last_run_timestamp",    "Last run unix timestamp")
next_run_g    = Gauge("autodiscovery_next_run_timestamp",    "Next run unix timestamp")

# ── Real-time EC2 state metrics (scraped every 30s) ─────────────────
# These are labeled gauges — one time series per instance
ec2_state_g = Gauge(
    "ec2_instance_state",
    "EC2 instance state: 1=running 0=stopped. Updated every 30s via AWS EC2 API.",
    ["instance_id", "instance_name", "instance_type", "region", "az", "os", "env", "account"]
)
ec2_running_total_g = Gauge(
    "ec2_running_total",
    "Total number of running EC2 instances (live from AWS EC2 API)"
)
ec2_stopped_total_g = Gauge(
    "ec2_stopped_total",
    "Total number of stopped EC2 instances (live from AWS EC2 API)"
)

app = FastAPI(title="EC2 Auto-Discovery v4", version="4.0.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

scheduler    = AsyncIOScheduler()
last_result  = {}
run_count    = 0
next_run_at  = None

# Track known instance label sets so we can clear stale ones
_known_instance_labels: set = set()


def poll_ec2_state():
    """
    Fast EC2 state poll — calls AWS EC2 API directly.
    Updates ec2_instance_state gauge for every instance.
    Takes ~1-2 seconds. No CloudWatch involved — INSTANT state.
    Called every STATE_INTERVAL_SECONDS (default 30s).
    """
    global _known_instance_labels

    try:
        running_count = 0
        stopped_count = 0
        current_labels = set()

        for region in REGIONS:
            ec2 = boto3.client("ec2", region_name=region)
            filters = []
            if TAG_FILTER_KEY:
                filters.append({"Name": f"tag:{TAG_FILTER_KEY}", "Values": [TAG_FILTER_VAL]})

            # Fetch ALL instances (running + stopped) for accurate state
            paginator = ec2.get_paginator("describe_instances")
            for page in paginator.paginate(Filters=filters):
                for res in page["Reservations"]:
                    for inst in res["Instances"]:
                        state = inst["State"]["Name"]
                        # Skip terminated/terminating — they're gone
                        if state in ("terminated", "terminating"):
                            continue

                        tags         = {t["Key"]: t["Value"] for t in inst.get("Tags", [])}
                        iid          = inst["InstanceId"]
                        name         = tags.get("Name", iid)
                        itype        = inst["InstanceType"]
                        az           = inst["Placement"]["AvailabilityZone"]
                        plat         = "windows" if inst.get("Platform", "").lower() == "windows" else "linux"
                        env          = tags.get("Environment", tags.get("Env", "production"))
                        is_running   = 1 if state == "running" else 0

                        label_key = (iid, region)
                        current_labels.add(label_key)

                        ec2_state_g.labels(
                            instance_id=iid, instance_name=name,
                            instance_type=itype, region=region,
                            az=az, os=plat, env=env,
                            account=os.getenv("PRIMARY_ACCOUNT_NAME", "production")
                        ).set(is_running)

                        if is_running:
                            running_count += 1
                        else:
                            stopped_count += 1

        # Remove stale labels (terminated instances)
        stale = _known_instance_labels - current_labels
        for (iid, region) in stale:
            try:
                ec2_state_g.remove(iid, region)
            except Exception:
                pass
        _known_instance_labels = current_labels

        # Update totals
        ec2_running_total_g.set(running_count)
        ec2_stopped_total_g.set(stopped_count)

        logger.info("⚡ State poll: %d running, %d stopped", running_count, stopped_count)

    except Exception as e:
        logger.error("State poll failed: %s", e)


async def run_collection():
    global last_result, run_count, next_run_at

    run_count  += 1
    start       = datetime.now(timezone.utc)
    next_run_at = start + timedelta(minutes=INTERVAL)
    next_run_g.set(next_run_at.timestamp())

    logger.info("══════════════════════════════════════════════")
    logger.info("🔍 EC2 COLLECTION #%d — %s UTC", run_count, start.strftime("%H:%M:%S"))
    logger.info("   Next run: %s UTC", next_run_at.strftime("%H:%M:%S"))
    logger.info("══════════════════════════════════════════════")

    try:
        loop   = asyncio.get_event_loop()
        result = await loop.run_in_executor(None, collect_and_write)

        duration = (datetime.now(timezone.utc) - start).total_seconds()
        result["duration_seconds"] = round(duration, 2)
        result["timestamp"]        = start.isoformat()
        result["run_number"]       = run_count
        result["next_run_at"]      = next_run_at.isoformat()
        last_result                = result

        # Update self-metrics
        runs_total.inc()
        instances_g.set(result["total"])
        running_g.set(result["running"])
        duration_g.set(duration)
        last_run_g.set(start.timestamp())

        logger.info("✅ Collection #%d done in %.1fs — %d instances (%d running)",
                    run_count, duration, result["total"], result["running"])

    except Exception as e:
        errors_total.inc()
        logger.error("❌ Collection #%d failed: %s", run_count, e, exc_info=True)
        last_result = {"error": str(e), "run_number": run_count}


@app.on_event("startup")
async def startup():
    os.makedirs(PROM_DIR, exist_ok=True)

    logger.info("╔══════════════════════════════════════════════════╗")
    logger.info("║  EC2 AUTO-DISCOVERY AGENT v5 — INSTANT STATE    ║")
    logger.info("╠══════════════════════════════════════════════════╣")
    logger.info("║  State poll : every %ds (AWS EC2 API — instant) ║", STATE_INTERVAL)
    logger.info("║  CW metrics : every %d minutes                  ║", INTERVAL)
    logger.info("║  Regions    : %-33s ║", os.getenv("AWS_REGIONS", "us-east-1"))
    logger.info("╚══════════════════════════════════════════════════╝")

    # ── Fast state poll every 30s (EC2 API — no CloudWatch delay) ───
    loop = asyncio.get_event_loop()
    scheduler.add_job(
        lambda: loop.run_in_executor(None, poll_ec2_state),
        trigger=IntervalTrigger(seconds=STATE_INTERVAL),
        id="ec2-state-poll",
        max_instances=1,
        coalesce=True,
    )

    # ── CloudWatch metrics collection every 2 min ────────────────────
    scheduler.add_job(
        run_collection,
        trigger=IntervalTrigger(minutes=INTERVAL),
        id="ec2-collect",
        max_instances=1,
        coalesce=True,
    )
    scheduler.start()

    # Run both immediately on startup
    loop.run_in_executor(None, poll_ec2_state)
    asyncio.create_task(run_collection())
    logger.info("🚀 State poll + collection starting now...")


@app.on_event("shutdown")
async def shutdown():
    scheduler.shutdown(wait=False)


@app.get("/health")
async def health():
    now  = datetime.now(timezone.utc)
    secs = int((next_run_at - now).total_seconds()) if next_run_at and next_run_at > now else 0
    prom_file = os.path.join(PROM_DIR, "ec2_metrics.prom")
    return {
        "status":               "ok",
        "timestamp":            now.isoformat(),
        "interval_minutes":     INTERVAL,
        "next_scan_in_seconds": secs,
        "next_scan_at":         next_run_at.isoformat() if next_run_at else None,
        "total_runs":           run_count,
        "instances_total":      last_result.get("total", 0),
        "instances_running":    last_result.get("running", 0),
        "textfile_exists":      os.path.exists(prom_file),
        "textfile_path":        prom_file,
    }


@app.get("/metrics")
async def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.get("/status")
async def status():
    return last_result or {"message": "First collection in progress..."}


@app.get("/instances")
async def instances():
    """Show what's in the textfile Prometheus is reading."""
    prom_file = os.path.join(PROM_DIR, "ec2_metrics.prom")
    if not os.path.exists(prom_file):
        return {"error": "No textfile yet — collection in progress"}
    with open(prom_file) as f:
        content = f.read()
    # Extract instance names from the file
    instances_found = []
    for line in content.splitlines():
        if line.startswith("ec2_instance_info{") and not line.startswith("#"):
            instances_found.append(line)
    return {
        "count":      len(instances_found),
        "instances":  instances_found,
        "file_lines": content.count("\n"),
    }


@app.post("/collect")
async def trigger():
    asyncio.create_task(run_collection())
    return {"message": "Collection triggered — check /status in 15 seconds"}


@app.get("/debug")
async def debug():
    import boto3
    result = {
        "env": {
            "AWS_DEFAULT_REGION": os.getenv("AWS_DEFAULT_REGION", "NOT SET"),
            "AWS_REGIONS":        os.getenv("AWS_REGIONS", "NOT SET"),
            "PROM_TEXTFILE_DIR":  PROM_DIR,
        },
        "textfile": None,
        "aws_identity": None,
        "aws_error":    None,
        "ec2_found":    [],
    }

    # Check textfile
    prom_file = os.path.join(PROM_DIR, "ec2_metrics.prom")
    if os.path.exists(prom_file):
        with open(prom_file) as f:
            content = f.read()
        result["textfile"] = {
            "exists": True,
            "lines": content.count("\n"),
            "preview": content[:500],
        }
    else:
        result["textfile"] = {"exists": False, "path": prom_file}

    # AWS identity
    try:
        sts = boto3.client("sts")
        identity = sts.get_caller_identity()
        result["aws_identity"] = {"account": identity["Account"], "arn": identity["Arn"]}
    except Exception as e:
        result["aws_error"] = str(e)

    # EC2 list
    try:
        ec2 = boto3.client("ec2", region_name=os.getenv("AWS_DEFAULT_REGION", "us-east-1"))
        resp = ec2.describe_instances()
        for res in resp["Reservations"]:
            for inst in res["Instances"]:
                tags = {t["Key"]: t["Value"] for t in inst.get("Tags", [])}
                result["ec2_found"].append({
                    "id":    inst["InstanceId"],
                    "name":  tags.get("Name", inst["InstanceId"]),
                    "state": inst["State"]["Name"],
                    "type":  inst["InstanceType"],
                })
    except Exception as e:
        result["aws_error"] = (result.get("aws_error") or "") + f" | EC2: {e}"

    return result
