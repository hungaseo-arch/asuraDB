import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface ActionItem { task: string; owner: string | null; due: string | null }
interface SummaryJSON {
  summary:      string;
  agenda:       string[];
  decisions:    string[];
  action_items: ActionItem[];
  next_meeting: string | null;
}

const SYSTEM_PROMPT = `당신은 회의록 분석 전문가입니다. 주어진 회의록을 분석하여 반드시 아래 JSON 형식만 출력하세요. 설명·마크다운 없이 순수 JSON만 출력하세요.

{"summary":"전체 회의 내용 2~3문장 요약","agenda":["논의된 주요 안건"],"decisions":["확정된 결정사항"],"action_items":[{"task":"할 일","owner":"담당자 또는 null","due":"기한 또는 null"}],"next_meeting":"다음 회의 일정 또는 null"}`;

// ── Claude Haiku ────────────────────────────────────────────────────────────
async function summarizeWithClaude(transcript: string): Promise<SummaryJSON> {
  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'x-api-key':         Deno.env.get('ANTHROPIC_API_KEY')!,
      'anthropic-version': '2023-06-01',
      'content-type':      'application/json',
    },
    body: JSON.stringify({
      model:      'claude-haiku-4-5-20251001',
      max_tokens: 1024,
      system:     SYSTEM_PROMPT,
      messages:   [{ role: 'user', content: `회의록:\n${transcript}` }],
    }),
  });

  if (!res.ok) throw new Error(`Claude API error: ${res.status}`);
  const data = await res.json();
  const content: string = data?.content?.[0]?.text ?? '';
  return JSON.parse(content) as SummaryJSON;
}

// ── 요약 엔진: Claude Haiku 통일 ─────────────────────────────────────────────
async function summarize(transcript: string): Promise<SummaryJSON> {
  if (Deno.env.get('ANTHROPIC_API_KEY')) return summarizeWithClaude(transcript);
  throw new Error('ANTHROPIC_API_KEY가 설정되지 않았습니다. Supabase Secrets에 추가하세요.');
}

// ── Edge Function 엔트리포인트 ─────────────────────────────────────────────────
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: corsHeaders });

  try {
    const { transcript, title, meeting_date, participants } = await req.json() as {
      transcript:    string;
      title?:        string | null;
      meeting_date?: string | null;
      participants?: string[];
    };

    if (!transcript?.trim()) {
      return new Response(
        JSON.stringify({ error: '회의록 텍스트가 필요합니다' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const summary = await summarize(transcript);

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    const { data, error } = await supabase
      .from('meeting_summaries')
      .insert({
        title:          title          ?? null,
        meeting_date:   meeting_date   ?? null,
        participants:   participants   ?? [],
        raw_transcript: transcript,
        summary,
        status: 'done',
      })
      .select('id')
      .single();

    if (error) throw error;

    return new Response(
      JSON.stringify({ id: data.id, summary }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: String(err) }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});
