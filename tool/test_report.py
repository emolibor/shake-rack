"""flutter test --machine çıktısından başarısız testleri GitHub hata notuna çevirir."""
import json, sys

tests, failed = {}, 0
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    line = line.strip()
    if not line.startswith("{"):
        continue
    try:
        e = json.loads(line)
    except ValueError:
        continue
    t = e.get("type")
    if t == "testStart":
        tests[e["test"]["id"]] = {"name": e["test"]["name"], "err": []}
    elif t == "error":
        tests.setdefault(e["testID"], {"name": "?", "err": []})["err"].append(
            (e.get("error") or "") + "\n" + (e.get("stackTrace") or "")[:600])
    elif t == "testDone" and e.get("result") != "success" and not e.get("hidden"):
        failed += 1
        info = tests.get(e["testID"], {"name": "?", "err": []})
        msg = "\n".join(info["err"])[:1800].replace("%", "%25").replace("\r", "").replace("\n", "%0A")
        title = info["name"].replace(",", " ").replace("::", " ")[:120]
        print(f"::error title={title}::{msg}")
print(f"{failed} başarısız test")
sys.exit(1 if failed else 0)
