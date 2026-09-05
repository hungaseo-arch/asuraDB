// attendance-selfie-cleanup — 출퇴근 셀피 90일 보관 후 자동 삭제 (D4)
//
// pg_cron('attendance-selfie-cleanup', 매일 UTC 18:30 = Jakarta 01:30)
//   → trigger_attendance_selfie_cleanup() → pg_net POST (Authorization: service_role)
//   → 이 함수. collect-indicators 와 동일한 클라우드 배치 패턴(작업지시서 KPI지표_월별백필_2026 §7 참고).
//
// attendance.selfie_url 은 공개 URL 이 아니라 attendance-selfies 버킷 내부 경로
// (<employee_id>/<attendance_id>.jpg) 를 담는다. Storage 객체 삭제는 Storage API 가 있어야
// 실제 파일까지 지워지므로(순수 SQL DELETE FROM storage.objects 로는 보장 안 됨) 이 Edge Function 에서
// service_role 로 처리하고, 성공한 행만 attendance.selfie_url 을 NULL 로 비운다(감사기록·판정 이력은 남긴다).

import { createClient } from "jsr:@supabase/supabase-js@2";

const sb = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const BUCKET = "attendance-selfies";
const RETENTION_DAYS = 90;
const BATCH_LIMIT = 500; // 하루 한 번 실행이므로 이 이상 밀릴 일은 거의 없지만 안전장치로 상한을 둔다.

async function heartbeat(source: string) {
  await sb.from("collector_heartbeat").upsert(
    { source, last_run: new Date().toISOString() },
    { onConflict: "source" },
  );
}

Deno.serve(async (_req: Request) => {
  const json = (status: number, payload: unknown) =>
    new Response(JSON.stringify(payload), { status, headers: { "Content-Type": "application/json" } });

  try {
    const cutoff = new Date(Date.now() - RETENTION_DAYS * 86_400_000).toISOString();

    const { data: rows, error: selErr } = await sb
      .from("attendance")
      .select("id, selfie_url")
      .not("selfie_url", "is", null)
      .lt("check_time", cutoff)
      .limit(BATCH_LIMIT);
    if (selErr) throw new Error(`attendance 조회 실패: ${selErr.message}`);

    let deleted = 0, cleared = 0, failed = 0;
    for (const row of rows ?? []) {
      const path = row.selfie_url as string;
      const { error: rmErr } = await sb.storage.from(BUCKET).remove([path]);
      // 이미 지워졌거나(404) 원래 없던 파일도 DB 정리는 진행 — 그 외 오류만 실패로 남긴다.
      if (rmErr && !/not.?found/i.test(rmErr.message)) {
        failed++;
        console.error(`[attendance-selfie-cleanup] remove(${path}) 실패:`, rmErr.message);
        continue;
      }
      if (!rmErr) deleted++;

      const { error: updErr } = await sb.from("attendance").update({ selfie_url: null }).eq("id", row.id);
      if (updErr) {
        failed++;
        console.error(`[attendance-selfie-cleanup] attendance ${row.id} selfie_url 정리 실패:`, updErr.message);
        continue;
      }
      cleared++;
    }

    await heartbeat("edge_attendance_selfie_cleanup");
    return json(200, {
      ok: failed === 0,
      cutoff,
      scanned: rows?.length ?? 0,
      storageDeleted: deleted,
      dbCleared: cleared,
      failed,
    });
  } catch (e) {
    console.error("[attendance-selfie-cleanup] 실패:", e);
    return json(500, { ok: false, error: String(e) });
  }
});
