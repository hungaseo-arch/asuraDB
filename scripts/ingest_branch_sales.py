#!/usr/bin/env python3
"""지점 월별 판매 CSV → branch_sales_rows 적재.

집계 규칙(화면 기존값과 대조 검증 완료):
  · 금액은 'SO AMT (IDR)'(PPN 11% 제외분) 기준 — 'Total Amt' 아님
  · 카테고리별 Qty 합, destination 무관 전 행

주의 — CSV 레이아웃이 지점마다 다르다:
  스마랑에는 'Brand 2' 열이 있고 수라바야에는 없어 7번 이후 인덱스가 한 칸 밀린다.
  따라서 컬럼은 반드시 '헤더명'으로 찾는다(고정 인덱스 금지).

사용:
  python scripts/ingest_branch_sales.py semarang "<csv경로>" [--dry-run]
"""
import argparse, csv, json, os, re, sys, urllib.request

MON = {m: i + 1 for i, m in enumerate(
    ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"])}

# PIC(이름 일부) → staff.name 첫단어. 사용자 확인 완료(2026-07-15).
PIC_ALIAS = {"JOKO": "DJOKO", "UGI": "UGIH", "YONO": "SUSYONO", "SAMAN": "SANAM"}

# SO 번호의 거래처 코드 → 실제 거래처명. 원본 Buyer 열이 제품명으로 깨진 행 보정용.
SO_BUYER = {
    "NIS":  "CV. NASAMED INTI SUKSES",
    "TBSA": "PT. TUGU BETON SEMESTA ABADI",
    "BPT":  "PT. BAMBOO PUTRA TRANSINDO",
}


def norm(s: str) -> str:
    return re.sub(r"[^A-Z0-9]", "", (s or "").upper())


def num(s):
    s = (s or "").strip().replace(",", "")
    if s in ("", "-", "–"):
        return 0.0
    try:
        return float(s)
    except ValueError:
        return 0.0


def parse_date(s):
    m = re.match(r"^(\d{1,2})-([A-Za-z]{3})-(\d{2})$", (s or "").strip())
    if not m:
        return None
    d, mo, y = m.groups()
    mon = MON.get(mo.title())
    return f"20{y}-{mon:02d}-{int(d):02d}" if mon else None


def sb(env, path, method="GET", body=None):
    url = f"{env['SUPABASE_URL']}/rest/v1/{path}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("apikey", env["SUPABASE_SERVICE_KEY"])
    req.add_header("Authorization", f"Bearer {env['SUPABASE_SERVICE_KEY']}")
    req.add_header("Content-Type", "application/json")
    req.add_header("Prefer", "return=minimal")
    with urllib.request.urlopen(req) as r:
        raw = r.read()
        return json.loads(raw) if raw else None


def load_env():
    env = {}
    with open(os.path.join(os.path.dirname(__file__), "..", ".env")) as fh:
        for line in fh:
            if "=" in line and not line.strip().startswith("#"):
                k, v = line.split("=", 1)
                env[k.strip()] = v.strip().strip('"').strip("'")
    return env


def read_csv(path):
    with open(path, encoding="utf-8-sig", errors="replace") as fh:
        raw = list(csv.reader(fh))
    hi = next(i for i, r in enumerate(raw[:20])
              if "QTY" in ",".join(r).upper() and "BUYER" in ",".join(r).upper())
    hdr = [h.strip().upper() for h in raw[hi]]

    def col(*names):
        for n in names:
            if n in hdr:
                return hdr.index(n)
        return None

    ix = {
        "so": col("SO"), "date": col("DELIVERY DATE"), "pic": col("PIC"),
        "buyer": col("BUYER"), "dest": col("DESTINATION"), "cat": col("CATEGORY"),
        "sku": col("NO. ITEM"), "desc": col("DESCRIPTION"),
        "unit": col("DISCOUNTED UNIT", "UNIT (IDR)"), "qty": col("QTY"),
        "soamt": col("SO AMT (IDR)"), "tax": col("TAX AMT (IDR)"), "total": col("TOTAL AMT (IDR)"),
    }
    missing = [k for k, v in ix.items() if v is None]
    if missing:
        sys.exit(f"필수 컬럼 없음: {missing}\n헤더: {hdr}")
    return [r for r in raw[hi + 1:] if len(r) > max(ix.values()) and (r[0] or "").strip()], ix


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("branch", choices=["semarang", "surabaya"])
    ap.add_argument("csv_path")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    env = load_env()
    rows, ix = read_csv(a.csv_path)

    customers = sb(env, "customers?select=customer_code,customer_name&limit=2000")
    products  = sb(env, "products?select=sku&limit=2000")
    staff     = sb(env, "staff?select=nik,name&limit=500")
    cust_by = {norm(c["customer_name"]): c["customer_code"] for c in customers if c.get("customer_name")}
    sku_set = {norm(p["sku"]): p["sku"] for p in products if p.get("sku")}
    staff_by = {}
    for s in staff:
        staff_by.setdefault(norm((s.get("name") or "").split(" ")[0]), []).append(s["nik"])

    payload, stat = [], {"sku": 0, "cust": 0, "staff": 0, "so_fix": 0, "skipped": 0}
    for r in rows:
        d = parse_date(r[ix["date"]])
        if not d:
            stat["skipped"] += 1
            continue

        buyer_raw = r[ix["buyer"]].strip()
        so = r[ix["so"]].strip()
        notes = []

        # Buyer 열이 회사명이 아니라 제품명으로 깨진 행 → SO 번호의 거래처 코드로 보정
        buyer = buyer_raw
        if not re.match(r"^(PT|CV)[\.\s]", buyer_raw.upper()):
            for code, name in SO_BUYER.items():
                if re.search(rf"[/\-]{code}[/\-]", so.upper()) or so.upper().startswith(f"PO/{code}"):
                    buyer, _ = name, notes.append("buyer=so_derived")
                    stat["so_fix"] += 1
                    break

        cust = cust_by.get(norm(buyer))
        if cust:
            stat["cust"] += 1
        else:
            notes.append("customer=none")

        sku_raw = r[ix["sku"]].strip()
        sku = sku_set.get(norm(sku_raw))
        if sku:
            stat["sku"] += 1
        else:
            notes.append("sku=none")

        pic_raw = r[ix["pic"]].strip()
        key = PIC_ALIAS.get(norm(pic_raw), norm(pic_raw))
        hits = staff_by.get(key, [])
        nik = hits[0] if len(hits) == 1 else None
        if nik:
            stat["staff"] += 1
        else:
            notes.append("staff=none" if not hits else "staff=ambiguous")

        payload.append({
            "branch": a.branch, "so": so or None, "delivery_date": d,
            "pic": pic_raw or None, "buyer": buyer or None, "sku_raw": sku_raw or None,
            "destination": r[ix["dest"]].strip().lower() or None,
            "category": r[ix["cat"]].strip().upper(),
            "description": r[ix["desc"]].strip() or None,
            "sku": sku, "customer_code": cust, "staff_nik": nik,
            "link_note": ",".join(notes) or "exact",
            "unit_price": num(r[ix["unit"]]) or None,
            "qty": num(r[ix["qty"]]), "so_amt": num(r[ix["soamt"]]),
            "tax_amt": num(r[ix["tax"]]) or None, "total_amt": num(r[ix["total"]]) or None,
            "source_file": os.path.basename(a.csv_path),
        })

    n = len(payload)
    print(f"파싱 {n}행 (스킵 {stat['skipped']})")
    print(f"  SKU 링크    {stat['sku']}/{n}")
    print(f"  거래처 링크 {stat['cust']}/{n}   (SO번호 보정 {stat['so_fix']}행)")
    print(f"  담당자 링크 {stat['staff']}/{n}")
    if a.dry_run:
        print("dry-run — 적재 안 함")
        return

    # 해당 지점 전량 교체 (CSV 가 그 지점의 전체 이력)
    sb(env, f"branch_sales_rows?branch=eq.{a.branch}", method="DELETE")
    for i in range(0, n, 500):
        sb(env, "branch_sales_rows", method="POST", body=payload[i:i + 500])
    print(f"적재 완료: {a.branch} {n}행")


if __name__ == "__main__":
    main()
