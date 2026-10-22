"""Jednorazowo importuje plan npoint do production_schedule_state.

Ustaw SUPABASE_URL oraz SUPABASE_SERVICE_ROLE_KEY i uruchom:
  python scripts/migrate_npoint_to_supabase.py
"""
import json
import os
from datetime import datetime, timezone
from urllib.request import Request, urlopen

NPOINT_URL = "https://api.npoint.io/995f8770744c6ed63d0f"
url = os.environ.get("SUPABASE_URL", "").rstrip("/")
key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
if not url or not key:
    raise SystemExit("Ustaw SUPABASE_URL i SUPABASE_SERVICE_ROLE_KEY.")
with urlopen(NPOINT_URL, timeout=30) as response:
    payload = json.load(response)
if not isinstance(payload, dict) or not isinstance(payload.get("assignments"), list):
    raise SystemExit("Dane npoint mają nieprawidłowy format.")
body = json.dumps({"id":1,"payload":payload,"updated_at":datetime.now(timezone.utc).isoformat()}).encode()
request = Request(url + "/rest/v1/production_schedule_state?on_conflict=id", data=body, method="POST", headers={"apikey":key,"Authorization":"Bearer "+key,"Content-Type":"application/json","Prefer":"resolution=merge-duplicates,return=minimal"})
with urlopen(request, timeout=30): pass
print("Migracja npoint zakończona.")
