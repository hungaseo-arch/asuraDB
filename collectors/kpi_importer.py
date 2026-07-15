"""
사업 실적 KPI importer — 연도별 사업계획 CSV(목표/실적) → kpi_metrics / kpi_monthly 적재.

입력: data/kpi/<YYYY>.csv  (사업계획 시트를 CSV로 저장한 파일; 연도별 1개)
  · 시트 구조: "1. TARGET/목표" 섹션 + "2. ACHIEVEMENT/실적" 섹션 (+ "3. …" 이후 무시)
  · 연도마다 제품 분류(Radial/Bias/Solid/Tire/LTR·TBR …)가 달라도 PRODUCT_MAP 으로 흡수.
  · 인코딩(UTF-8 / CP949 / 이중인코딩 mojibake) 자동 복구.

매핑: Radial·Tire·LTR/TBR → TBR, Bias → TBB, Solid·Pneumatic → IND,
      OTR → OTR, AGR → AGR, Vulkan → Vulkan, Tube → Tube, Flap → Flap.

실행:
  uv run python collectors/kpi_importer.py --dry-run     # DB 미반영, 파싱·검증만 출력
  uv run python collectors/kpi_importer.py               # Supabase upsert (SUPABASE_SERVICE_KEY 필요)
  uv run python collectors/kpi_importer.py --dir path/   # 입력 디렉터리 지정
"""
from __future__ import annotations

import csv
import io
import os
import re
import sys
from collections import defaultdict

# ── 제품 매핑 ──────────────────────────────────────────────────────────────────

PRODUCT_MAP = {
    # → TBR
    "tire": "TBR", "radial": "TBR", "ltr/tbr": "TBR", "tbr": "TBR",
    # → TBB
    "bias": "TBB", "tbb": "TBB",
    "otr": "OTR",
    "agr": "AGR",
    # → IND (Solid + Pneumatic)
    "solid": "IND", "pneumatic": "IND", "ind": "IND",
    "vulkan": "Vulkan",
    "tube": "Tube",
    "flap": "Flap",
    # 한글 라벨 (2022 실적 등) — 정상 UTF-8
    "솔리드": "IND", "공압": "IND",
    "튜브": "Tube", "플랩": "Flap",
}

# 2022 실적 시트의 한글 라벨은 mojibake(저장 시 제어 바이트가 손실)라 정상 한글로 복구가
# 불가능하다. → 파일에 실제 담긴 바이트열(latin-1 디코드)을 키로 사용한다.
# (소스에 깨진 글자를 그대로 두지 않도록, 바이트열 + 정상 라벨 주석으로 명시. byte-exact 검증됨)
for _raw, _code in (
    ((0xEC, 0xEB, 0xA6, 0xAC, 0xEB), "IND"),   # 솔리드
    ((0xED, 0x20, 0xEB, 0xB8),       "Tube"),  # 튜브
    ((0xED, 0x20, 0xEB, 0xA9),       "Flap"),  # 플랩
):
    PRODUCT_MAP[bytes(_raw).decode("latin-1")] = _code

# ⚠ "타이어"(및 그 mojibake) 는 의도적으로 매핑에서 제외한다.
#   TBR = Truck & Bus 'Radial' 특정 제품이라 "타이어"(=전체 타이어 집계)를 대변할 수 없음.
#   실제 시트에서 "타이어" 행은 항상 '판매금액 달성률(%)' 요약 행(값이 100%·8.4% 등 퍼센트)이라
#   num()이 None 처리 → 기록 대상 아님. 실제 TBR 데이터는 Tire/Radial/LTR·TBR/TBR. 라벨에서 온다.

CODE = {  # 표준 제품 → metric id suffix
    "TBR": "tbr", "TBB": "tbb", "OTR": "otr", "AGR": "agr",
    "IND": "ind", "Vulkan": "vulkan", "Tube": "tube", "Flap": "flap",
}

# 지표 정의 (kpi_metrics) — 마이그레이션과 동일, 멱등 upsert
METRIC_DEFS = []
for _p, _c in CODE.items():
    METRIC_DEFS.append((f"q_{_c}", "market", _p, "qty", f"{_p} 판매량", "pcs"))
    METRIC_DEFS.append((f"a_{_c}", "market", _p, "amount", f"{_p} 판매금액", "USD"))
METRIC_DEFS += [
    ("fin_sales", "internal", None, "financial", "재무매출", "USD"),
    ("fin_sga",   "internal", None, "financial", "판관비", "USD"),
    ("fin_op",    "internal", None, "financial", "영업이익", "USD"),
    ("fin_ord",   "internal", None, "financial", "경상이익", "USD"),
]

QTY_MARKERS    = {"qty", "판매수량", "íë§¤ìë"}        # mojibake 판매수량
AMOUNT_MARKERS = {"amt", "판매금액", "íë§¤ê¸ì¡"}        # mojibake 판매금액

# 재무 라벨: 정상 한글 + mojibake 양쪽 매칭
FIN_LABELS = {
    "fin_sales": {"재무매출", "ì¬ë¬´ë§¤ì¶"},
    "fin_sga":   {"판관비", "íê´ë¹"},
    "fin_op":    {"영업이익", "ììì´ìµ"},
    "fin_ord":   {"경상이익", "ê²½ìì´ìµ"},
}

# ── 인코딩 복구 ────────────────────────────────────────────────────────────────

def read_text(path: str) -> str:
    raw = open(path, "rb").read()
    text = None
    for enc in ("utf-8-sig", "cp949", "euc-kr"):
        try:
            text = raw.decode(enc)
            break
        except UnicodeDecodeError:
            continue
    if text is None:
        text = raw.decode("latin-1")
    # 이중 인코딩 mojibake (UTF-8 바이트가 latin-1 로 표시된 경우) 복구
    if not re.search(r"[가-힣]", text) and re.search(r"[ÃÂìëíê]", text):
        try:
            fixed = text.encode("latin-1").decode("utf-8")
            if re.search(r"[가-힣]", fixed):
                text = fixed
        except (UnicodeEncodeError, UnicodeDecodeError):
            pass
    # 선두 BOM 제거 (정상 '﻿' + mojibake 'ï»¿')
    text = text.lstrip("﻿")
    if text.startswith("ï»¿"):
        text = text[3:]
    return text

# ── 셀 파싱 ────────────────────────────────────────────────────────────────────

_NULLS = {"", "-", "–", "—", "``", "`", "#value!", "#div/0!", "n/a", "전체", "연간", "연간목표"}

def num(s: str):
    s = s.strip().strip('"').strip()
    if s.lower() in _NULLS:
        return None
    s = s.replace(",", "").replace(" ", "")
    try:
        return float(s)
    except ValueError:
        return None

def detect_section(cells):
    """'1.'→target, '2.'→achv, '3.'→stop, else None."""
    for c in cells:
        # "N. 제목" 형태만 섹션 헤더로 — '3.0%' 같은 값 셀 오인 방지 (점 뒤 공백 필수)
        m = re.match(r"^\s*([123])\.\s+\S", c.strip())
        if m:
            return {"1": "target", "2": "achv", "3": "stop"}[m.group(1)]
    return None

def find_sum_index(cells):
    for i, c in enumerate(cells):
        if c.strip().strip('"').strip() in ("Sum", "합계", "í©ê³"):   # mojibake 합계 = 'í©ê³'
            return i
    return None

def classify_financial(label: str):
    l = label.strip().strip('"').strip()
    if "률" in l or "달성" in l or "ë¥" in l:   # 비율/달성률 행 제외 (mojibake 률 = 'ë¥')
        return None
    for metric, toks in FIN_LABELS.items():
        if l in toks:
            return metric
    return None

def map_product(label: str):
    l = label.strip().strip('"').strip().rstrip(".").lower()
    return PRODUCT_MAP.get(l)

def marker_kind(label: str):
    l = label.strip().strip('"').strip().lower()
    if l in QTY_MARKERS:
        return "qty"
    if l in AMOUNT_MARKERS:
        return "amount"
    return None

# ── 파일 파싱 ──────────────────────────────────────────────────────────────────

def parse_file(path: str, year: int, agg: dict, sums: dict, warns: list):
    rows = list(csv.reader(io.StringIO(read_text(path))))
    section = None      # 'target' | 'achv'
    col = None          # 'target' | 'actual'
    J = None
    current_kind = None
    qty_seen = set()

    def record(metric_id, months, sum_cell):
        for i, v in enumerate(months):
            if v is None:
                continue
            ym = f"{year}-{i + 1:02d}"
            agg[(metric_id, ym)][col] = v
        # 검증용: 월합 vs 시트 Sum
        msum = sum(v for v in months if v is not None)
        if sum_cell is not None and abs(msum - sum_cell) > 5:
            warns.append(f"  [{year} {section}] {metric_id}: 월합 {msum:,.0f} ≠ 시트Sum {sum_cell:,.0f}")
        sums[(year, col, metric_id)] = msum

    for raw in rows:
        cells = [c for c in raw]
        sec = detect_section(cells)
        if sec == "stop":
            break
        if sec in ("target", "achv"):
            section = sec
            col = "target" if sec == "target" else "actual"
            J = None; current_kind = None; qty_seen = set()
            continue
        if section is None:
            continue

        s_idx = find_sum_index(cells)
        if s_idx is not None and s_idx >= 14:
            J = s_idx - 12
            current_kind = None; qty_seen = set()
            continue
        if J is None:
            continue

        def cell(idx):
            return cells[idx].strip().strip('"').strip() if 0 <= idx < len(cells) else ""

        kind_col = cell(J - 5)
        prod_col = cell(J - 4)
        months = [num(cells[J + i]) if J + i < len(cells) else None for i in range(12)]
        sum_cell = num(cells[J + 12]) if J + 12 < len(cells) else None

        km = marker_kind(kind_col)
        if km:
            current_kind = km

        fin = classify_financial(kind_col)
        if fin:
            record(fin, months, sum_cell)
            continue

        code = map_product(prod_col)
        if code:
            k = current_kind
            if k == "qty" and code in qty_seen:   # 2023 시트 라벨 오류(AMT 블록도 'Qty') 보정
                k = "amount"; current_kind = "amount"
            if k is None:
                warns.append(f"  [{year} {section}] kind 미상: {prod_col}")
                continue
            if k == "qty":
                qty_seen.add(code)
            record(("q_" if k == "qty" else "a_") + CODE[code], months, sum_cell)
            continue

        # AMT 블록의 'Total' → 재무매출
        if prod_col.lower() in ("total", "합계") and current_kind == "amount":
            record("fin_sales", months, sum_cell)
            continue

# ── Supabase upsert ────────────────────────────────────────────────────────────

def upsert(agg: dict):
    from dotenv import load_dotenv
    load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))
    from supabase import create_client

    sb = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])

    # 1) 지표 정의
    metric_rows = [
        {"id": mid, "grp": grp, "product": prod, "kind": kind,
         "name_ko": name, "name_en": None, "unit": unit, "sort_order": i * 10}
        for i, (mid, grp, prod, kind, name, unit) in enumerate(METRIC_DEFS)
    ]
    sb.table("kpi_metrics").upsert(metric_rows, on_conflict="id").execute()

    # 2) 월별 목표/실적
    #    source='manual' 행(화면 입력창 저장분)은 건너뛴다 — 안 그러면 수기 입력이 CSV 로 되돌아간다.
    #    CSV 를 다시 진실원천으로 삼으려면 해당 행의 source 를 'csv' 로 바꾸고 재실행.
    locked = set()
    off = 0
    while True:
        res = (sb.table("kpi_monthly")
                 .select("metric_id,year_month")
                 .eq("source", "manual")
                 .range(off, off + 999).execute())
        locked.update((r["metric_id"], r["year_month"]) for r in res.data)
        if len(res.data) < 1000:
            break
        off += 1000

    rows = [
        {"metric_id": mid, "year_month": ym,
         "target": vals.get("target"), "actual": vals.get("actual"), "source": "csv"}
        for (mid, ym), vals in agg.items()
        if (mid, ym) not in locked
    ]
    for i in range(0, len(rows), 500):
        sb.table("kpi_monthly").upsert(
            rows[i:i + 500], on_conflict="metric_id,year_month"
        ).execute()
    return len(metric_rows), len(rows), len(locked)

# ── Entry ──────────────────────────────────────────────────────────────────────

def run():
    args = sys.argv[1:]
    dry = "--dry-run" in args
    data_dir = os.path.join(os.path.dirname(__file__), "..", "data", "kpi")
    if "--dir" in args:
        data_dir = args[args.index("--dir") + 1]

    files = sorted(
        f for f in os.listdir(data_dir) if re.fullmatch(r"\d{4}\.csv", f)
    )
    if not files:
        print(f"[kpi_importer] {data_dir} 에 <YYYY>.csv 파일이 없습니다.", file=sys.stderr)
        sys.exit(1)

    agg = defaultdict(dict)   # (metric_id, ym) -> {target, actual}
    sums = {}
    warns = []

    print(f"[kpi_importer] {len(files)}개 파일 파싱: {', '.join(files)}\n")
    for f in files:
        year = int(f[:4])
        parse_file(os.path.join(data_dir, f), year, agg, sums, warns)

    # 요약: 연도별 재무매출(실적) 월합
    print("연도별 재무매출(실적) 월합 / 영업이익(실적) 월합:")
    for year in sorted({y for (y, c, m) in sums}):
        s = sums.get((year, "actual", "fin_sales"))
        op = sums.get((year, "actual", "fin_op"))
        s_str = f"{s:,.0f}" if s is not None else "—"
        op_str = f"{op:,.0f}" if op is not None else "—"
        print(f"  {year}: 재무매출 {s_str:>14}   영업이익 {op_str:>12}")

    n_metrics = len({mid for (mid, ym) in agg})
    n_rows = len(agg)
    print(f"\n지표 {n_metrics}종, 월별 레코드 {n_rows}건 파싱 완료.")

    if warns:
        print(f"\n⚠️ 검증 경고 {len(warns)}건 (월합 ≠ 시트 Sum):")
        for w in warns:
            print(w)
    else:
        print("\n✓ 모든 행 월합 = 시트 Sum (검증 통과)")

    if dry:
        print("\n[dry-run] DB 미반영. 실제 적재: --dry-run 제거 후 재실행.")
        return

    nm, nr, nlock = upsert(agg)
    print(f"\n✓ Supabase upsert 완료: kpi_metrics {nm}건, kpi_monthly {nr}건")
    if nlock:
        print(f"  ↳ 화면 입력창 저장분(source=manual) {nlock}건은 건너뜀 — CSV 로 되돌리려면 해당 행 source 를 'csv' 로 변경 후 재실행")


if __name__ == "__main__":
    run()
