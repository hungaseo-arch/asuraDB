"""
경쟁사 가격 모니터링 — SKU 마스터 & 수동 입력 가이드

목적:
  매주 Tokopedia / Shopee / Bukalapak 에서 경쟁사 타이어 가격을 수집하고
  자사 평균가 대비 지수(Index = 자사평균/경쟁사평균 × 100)를 산출해
  indicator_history 의 competitor_price 지표에 upsert 한다.

  지수 > 100 → 자사가 비쌈 (가격 경쟁력 약화)
  지수 < 100 → 자사가 저렴 (가격 경쟁력 우위)
  지수 = 100 → 동일

운영 방식:
  자동 크롤링은 마켓플레이스 ToS 문제로 권장하지 않음.
  → 매주 금요일 직원이 아래 SKU 표를 보며 각 마켓에서 가격을 직접 조회 후
     이 스크립트에 가격 배열을 입력해 실행.

실행: uv run python collectors/competitor_sku_list.py
"""
import os
from datetime import date

from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))

from supabase import create_client

_sb = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])

# ── SKU 마스터 (30개) ────────────────────────────────────────────────────────
# 조회 마켓: Tokopedia(T), Shopee(S) 각 1~2개 대표 셀러
# 가격 단위: IDR (루피아), 천 단위 구분 없이 정수
# 자사 제품: PT Ascendo (GT Radial, Forceum 등)
# 경쟁 브랜드: Bridgestone, Michelin, Hankook, Achilles, Dunlop

SKU_MASTER: list[dict] = [
    # ── TBR (Truck & Bus Radial) ── 10 SKUs ─────────────────────────────────
    {"sku": "TBR-01", "category": "TBR", "size": "11R22.5", "brand_self": "GT Radial GT978+",    "brand_comp": "Bridgestone R-150F"},
    {"sku": "TBR-02", "category": "TBR", "size": "11R22.5", "brand_self": "GT Radial GT978+",    "brand_comp": "Michelin X MultiWay"},
    {"sku": "TBR-03", "category": "TBR", "size": "295/80R22.5","brand_self": "GT Radial GT969", "brand_comp": "Hankook AL10"},
    {"sku": "TBR-04", "category": "TBR", "size": "295/80R22.5","brand_self": "GT Radial GT969", "brand_comp": "Dunlop SP372"},
    {"sku": "TBR-05", "category": "TBR", "size": "12R22.5", "brand_self": "GT Radial GT979",    "brand_comp": "Bridgestone M749"},
    {"sku": "TBR-06", "category": "TBR", "size": "10.00R20", "brand_self": "GT Radial GT275",   "brand_comp": "Achilles 315"},
    {"sku": "TBR-07", "category": "TBR", "size": "750R16",  "brand_self": "Forceum T90",         "brand_comp": "Achilles Multivan"},
    {"sku": "TBR-08", "category": "TBR", "size": "825R20",  "brand_self": "GT Radial GT275",    "brand_comp": "Bridgestone R150"},
    {"sku": "TBR-09", "category": "TBR", "size": "1000R20", "brand_self": "GT Radial GT979",    "brand_comp": "Michelin XZY"},
    {"sku": "TBR-10", "category": "TBR", "size": "385/65R22.5","brand_self":"GT Radial GT969",  "brand_comp": "Hankook AH31"},

    # ── OTR (Off-The-Road / Mining) ── 8 SKUs ───────────────────────────────
    {"sku": "OTR-01", "category": "OTR", "size": "23.5R25", "brand_self": "GT Radial XT7",      "brand_comp": "Bridgestone VRTS"},
    {"sku": "OTR-02", "category": "OTR", "size": "26.5R25", "brand_self": "GT Radial XT7",      "brand_comp": "Michelin XTL"},
    {"sku": "OTR-03", "category": "OTR", "size": "29.5R25", "brand_self": "GT Radial XT-3",     "brand_comp": "Bridgestone VRDP"},
    {"sku": "OTR-04", "category": "OTR", "size": "17.5R25", "brand_self": "GT Radial XT7",      "brand_comp": "Dunlop SP T9"},
    {"sku": "OTR-05", "category": "OTR", "size": "14.00-24","brand_self": "GT Radial XT6",      "brand_comp": "Hankook E-3A"},
    {"sku": "OTR-06", "category": "OTR", "size": "16.00-25","brand_self": "GT Radial XT6",      "brand_comp": "Bridgestone VSDT"},
    {"sku": "OTR-07", "category": "OTR", "size": "20.5R25", "brand_self": "GT Radial XT7",      "brand_comp": "Michelin XADN"},
    {"sku": "OTR-08", "category": "OTR", "size": "24.00R35","brand_self": "GT Radial XT-3",     "brand_comp": "Bridgestone VRTS"},

    # ── IND (Industrial / Forklift — Solid & PNEU) ── 6 SKUs ───────────
    {"sku": "IND-01", "category": "IND", "size": "6.00-9",  "brand_self": "Forceum Solid F1",   "brand_comp": "Trelleborg T900"},
    {"sku": "IND-02", "category": "IND", "size": "7.00-12", "brand_self": "Forceum Solid F1",   "brand_comp": "Continental SC20"},
    {"sku": "IND-03", "category": "IND", "size": "8.25-15", "brand_self": "Forceum Solid F2",   "brand_comp": "Trelleborg T800"},
    {"sku": "IND-04", "category": "IND", "size": "28x9-15", "brand_self": "Forceum Pneu P1",    "brand_comp": "Hankook W-2"},
    {"sku": "IND-05", "category": "IND", "size": "18x7-8",  "brand_self": "Forceum Solid F1",   "brand_comp": "Solideal SKS777"},
    {"sku": "IND-06", "category": "IND", "size": "250-15",  "brand_self": "Forceum Pneu P2",    "brand_comp": "Camso SHL"},

    # ── AGR (Agriculture) ── 6 SKUs ─────────────────────────────────────────
    {"sku": "AGR-01", "category": "AGR", "size": "12.4-28", "brand_self": "GT Farm GT30",        "brand_comp": "BKT Agrimax"},
    {"sku": "AGR-02", "category": "AGR", "size": "14.9-28", "brand_self": "GT Farm GT30",        "brand_comp": "Bridgestone FL18"},
    {"sku": "AGR-03", "category": "AGR", "size": "18.4-34", "brand_self": "GT Farm GT35",        "brand_comp": "Michelin AgriBib"},
    {"sku": "AGR-04", "category": "AGR", "size": "11.2-24", "brand_self": "GT Farm GT25",        "brand_comp": "BKT TR135"},
    {"sku": "AGR-05", "category": "AGR", "size": "7.50-16", "brand_self": "GT Farm GT20",        "brand_comp": "Firestone F100"},
    {"sku": "AGR-06", "category": "AGR", "size": "9.5-24",  "brand_self": "GT Farm GT25",        "brand_comp": "Bridgestone FL627"},
]


def print_sku_table() -> None:
    """매주 가격 수집 시 참조할 SKU 목록 출력."""
    print("\n경쟁사 가격 수집 SKU 목록 (30개)")
    print("=" * 80)
    print(f"  {'SKU':<8} {'구분':<5} {'사이즈':<14} {'자사 제품':<24} {'경쟁사 제품'}")
    print("  " + "─" * 76)
    for s in SKU_MASTER:
        print(
            f"  {s['sku']:<8} {s['category']:<5} {s['size']:<14} "
            f"{s['brand_self']:<24} {s['brand_comp']}"
        )
    print("=" * 80)


def calculate_index(self_prices: list[float], comp_prices: list[float]) -> float:
    """
    가격 경쟁력 지수 = (자사 평균가 / 경쟁사 평균가) × 100
    지수 > 100 → 자사가 비쌈, < 100 → 자사가 저렴
    """
    avg_self = sum(self_prices) / len(self_prices)
    avg_comp = sum(comp_prices) / len(comp_prices)
    return (avg_self / avg_comp) * 100


def upsert_index(index_value: float, record_date: date, note: str = "") -> None:
    _sb.table("indicator_history").upsert(
        {
            "indicator_id": "competitor_price",
            "value": round(index_value, 2),
            "recorded_date": record_date.isoformat(),
            "note": note,
        },
        on_conflict="indicator_id,recorded_date",
    ).execute()


def run_manual_entry() -> None:
    """
    실무 담당자가 매주 금요일 가격 수집 후 배열에 직접 입력하는 섹션.
    아래 예시 데이터를 실제 조회값으로 교체 후 실행.
    """
    today = date.today()
    print(f"\n[competitor_sku_list] {today} 경쟁사 가격 지수 산출")

    # ── 아래 배열에 SKU별 실제 가격을 입력 (IDR 단위) ──────────────────────
    # 미조회 SKU는 None 으로 표시 → 자동 제외
    self_prices: list[float | None] = [
        # TBR 01~10
        None, None, None, None, None,
        None, None, None, None, None,
        # OTR 01~08
        None, None, None, None,
        None, None, None, None,
        # IND 01~06
        None, None, None, None, None, None,
        # AGR 01~06
        None, None, None, None, None, None,
    ]
    comp_prices: list[float | None] = [
        # TBR 01~10
        None, None, None, None, None,
        None, None, None, None, None,
        # OTR 01~08
        None, None, None, None,
        None, None, None, None,
        # IND 01~06
        None, None, None, None, None, None,
        # AGR 01~06
        None, None, None, None, None, None,
    ]
    # ──────────────────────────────────────────────────────────────────────────

    valid_self = [p for p in self_prices if p is not None]
    valid_comp = [p for p in comp_prices if p is not None]

    if len(valid_self) < 5 or len(valid_comp) < 5:
        print(
            "  [SKIP] 가격 데이터 부족 (최소 5개 SKU 필요).\n"
            "         self_prices / comp_prices 배열에 실제값 입력 후 재실행."
        )
        print_sku_table()
        return

    idx = calculate_index(valid_self, valid_comp)
    note = f"자사{len(valid_self)}개/경쟁사{len(valid_comp)}개 SKU 평균"
    upsert_index(idx, today, note)
    direction = "▲ 자사고가" if idx > 100 else ("▼ 자사저가" if idx < 100 else "─ 동일")
    print(f"  경쟁사 가격지수: {idx:.1f}  {direction}")
    print(f"  ({note})")
    print(f"[competitor_sku_list] 완료\n")


if __name__ == "__main__":
    run_manual_entry()
