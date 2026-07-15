"""
주간 모니터링 리포트 자동 생성 — Claude API 사용
실행: python scripts/generate_monitoring_report.py
"""
import json
import os
import sys
from datetime import date, timedelta

from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))

try:
    import anthropic
except ImportError:
    print("anthropic 미설치. pip install anthropic 실행 후 재시도하세요.", file=sys.stderr)
    sys.exit(1)

from supabase import create_client

_supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])
_claude = anthropic.Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])
_model = os.environ.get("CLAUDE_MODEL_AGENT", "claude-sonnet-4-6")


def get_week_label(d: date) -> str:
    return f"{d.isocalendar().year}-W{d.isocalendar().week:02d}"


def collect_snapshot() -> list[dict]:
    today = date.today()
    week_ago = today - timedelta(days=7)

    indicators = (
        _supabase.table("market_indicators")
        .select("id,name_ko,name_en,category,alert_level,unit")
        .order("sort_order")
        .execute()
        .data
    )

    snapshot = []
    for ind in indicators:
        rows = (
            _supabase.table("indicator_history")
            .select("value,recorded_date")
            .eq("indicator_id", ind["id"])
            .gte("recorded_date", week_ago.isoformat())
            .order("recorded_date", desc=True)
            .limit(8)
            .execute()
            .data
        )
        if not rows:
            continue

        current = rows[0]["value"]
        prev = rows[-1]["value"] if len(rows) > 1 else None
        change_pct = (
            round((current - prev) / prev * 100, 2)
            if prev and prev != 0
            else None
        )
        snapshot.append(
            {
                "id": ind["id"],
                "name_ko": ind["name_ko"],
                "name_en": ind["name_en"],
                "category": ind["category"],
                "alert_level": ind["alert_level"],
                "unit": ind["unit"],
                "current": current,
                "prev": prev,
                "change_pct": change_pct,
                "history": [{"date": r["recorded_date"], "value": r["value"]} for r in rows],
            }
        )
    return snapshot


SYSTEM_PROMPT = """
당신은 PT Ascendo International Indonesia의 주간 시장 모니터링 리포트를 작성하는 분석가입니다.
타이어 유통업 관점에서 원자재·환율·물류·정책 지표를 해석하고 경영진을 위한 인사이트를 제공하세요.

응답은 반드시 다음 JSON 형식으로 작성하세요:
{
  "executive_summary": "한국어 2~3문장 핵심 요약",
  "key_highlights": [{"indicator": "지표명", "signal": "🔴|🟡|🟢", "comment": "한 줄 설명"}],
  "category_analysis": {
    "commodity": "원자재 동향 분석",
    "fx": "환율 동향 분석",
    "freight": "물류/운임 동향 분석",
    "policy": "정책/거시경제 분석",
    "market": "시장/경쟁 분석",
    "internal": "재무 분석"
  },
  "risks": ["리스크 항목 1", "리스크 항목 2"],
  "opportunities": ["기회 항목 1", "기회 항목 2"],
  "recommendations": ["권고사항 1", "권고사항 2", "권고사항 3"]
}
""".strip()


def build_user_prompt(snapshot: list[dict], week: str) -> str:
    lines = [f"주간 리포트 기간: {week}", "", "── 지표 현황 ──"]
    for s in snapshot:
        chg = f" ({s['change_pct']:+.1f}%)" if s["change_pct"] is not None else ""
        lines.append(
            f"[{s['alert_level'].upper()}] {s['name_ko']} ({s['unit'] or '-'}): "
            f"{s['current']}{chg}"
        )
    return "\n".join(lines)


def run() -> None:
    today = date.today()
    week = get_week_label(today)
    print(f"[generate_report] {week} 리포트 생성 중...")

    snapshot = collect_snapshot()
    if not snapshot:
        print("수집된 지표 없음. 종료.", file=sys.stderr)
        sys.exit(1)

    user_prompt = build_user_prompt(snapshot, week)
    print(f"  → {len(snapshot)}개 지표 포함, Claude({_model}) 호출 중...")

    message = _claude.messages.create(
        model=_model,
        max_tokens=2048,
        system=SYSTEM_PROMPT,
        messages=[{"role": "user", "content": user_prompt}],
    )
    raw_text = message.content[0].text

    try:
        content = json.loads(raw_text)
    except json.JSONDecodeError:
        import re
        m = re.search(r"\{.*\}", raw_text, re.DOTALL)
        content = json.loads(m.group()) if m else {"raw": raw_text}

    _supabase.table("monitoring_reports").insert(
        {
            "report_date": today.isoformat(),
            "report_week": week,
            "content": content,
            "raw_markdown": raw_text,
        }
    ).execute()

    print(f"[generate_report] 완료 — {week} 리포트 저장됨")
    print(f"  요약: {content.get('executive_summary', '')[:80]}...")


if __name__ == "__main__":
    run()
