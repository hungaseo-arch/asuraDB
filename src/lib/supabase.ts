const SUPABASE_URL = import.meta.env.VITE_SB_URL as string;
const SUPABASE_KEY = import.meta.env.VITE_SB_KEY as string;

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
