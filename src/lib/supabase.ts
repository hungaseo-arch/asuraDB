const SUPABASE_URL = 'https://subatvlyfglztdmyexfl.supabase.co';
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InN1YmF0dmx5ZmdsenRkbXlleGZsIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3OTAzMjQ0NywiZXhwIjoyMDk0NjA4NDQ3fQ.4vJv9BOmP70MY4wm7VQZcAr5VTCGR6D6p1wAeNoYihk';

const HEADERS = {
  apikey: SUPABASE_KEY,
  Authorization: `Bearer ${SUPABASE_KEY}`,
  'Content-Type': 'application/json',
};

async function get<T>(table: string, params: Record<string, string>): Promise<T[]> {
  const qs = new URLSearchParams(params).toString();
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${table}?${qs}`, { headers: HEADERS });
  if (!res.ok) throw new Error(`Supabase ${table}: ${res.status}`);
  return res.json() as Promise<T[]>;
}

export const db = { get };
