#!/usr/bin/env python3
"""인건비 월간 반영 스크립트 (경영·성과 > 인건비 탭 + DB 직원 탭).

원천: HR(teddy@e.pthunga.com) 월간 메일 첨부
  - Rekap Gaji Ascendo Internasional, Priode <Mon YYYY>.xls   (4시트 = HQ/Karawang/Surabaya/Semarang)
  - kompensasi PKWT Ascendo <Pusat|WH Karawang|Cab Surabaya|Cab Semarang> ....xls
  - Insentive Sales ....xls                                    (있는 달만)
  - Salary Check List 3 Month Report <Mon YYYY>.xlsx           (검증 기준)

사용:
  # 1) Gmail RAW(JSON 저장본)에서 첨부 추출
  python3 scripts/payroll_monthly.py extract <gmail_raw.json> <outdir>
  # 2) 집계 + 검증 → 리포트(JSON)의 payroll_monthly.sql = 인건비 탭 SSOT(Supabase payroll_monthly) 반영 SQL
  #    (+ --sql 로 staff_payroll upsert SQL 생성, --apply 로 정적 fallback src/data/payrollMonthly.ts 갱신)
  python3 scripts/payroll_monthly.py run --period 2026-09 --dir <outdir> [--dir <rev_outdir>] \
      [--apply] [--sql /tmp/staff_payroll_2026-09.sql] [--override thr.HQ=268.9]

원칙:
  - 검증(blocking) 실패 시 종료코드 2, 파일을 수정하지 않는다.
  - 표준출력 리포트(JSON)에는 개인정보(성명·NIK·계좌·개인별 금액)를 싣지 않는다.
  - --sql 산출물에는 개인정보가 들어가므로 저장소 밖 경로에만 쓴다(커밋 금지).
의존성: xlrd(.xls), openpyxl(.xlsx)
"""
import argparse
import base64
import datetime as dt
import email
import json
import os
import re
import sys
from email import policy

TS_DEFAULT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'src', 'data', 'payrollMonthly.ts')
TABS = ['HQ', 'WH', 'SBY', 'SMG']
TAB_KEY = {'HQ': 'HQ Jakarta', 'WH': 'Cikarang/Karawang WH', 'SBY': 'Surabaya', 'SMG': 'Semarang'}
TAB_LOCATION = {'HQ': 'Jakarta', 'WH': 'Karawang', 'SBY': 'Surabaya', 'SMG': 'Semarang'}
COMPANY_ROW = {'HQ': 'HQ 자카르타 (본사)', 'WH': '찌까랑·까라왕 창고', 'SBY': '수라바야', 'SMG': '스마랑'}
BULAN = {'JANUARI': 1, 'FEBRUARI': 2, 'MARET': 3, 'APRIL': 4, 'MEI': 5, 'JUNI': 6, 'JULI': 7,
         'AGUSTUS': 8, 'SEPTEMBER': 9, 'OKTOBER': 10, 'NOVEMBER': 11, 'DESEMBER': 12}
MON_TOKENS = {1: ['JAN'], 2: ['FEB', 'PEB'], 3: ['MAR'], 4: ['APR'], 5: ['MEI', 'MAY'], 6: ['JUN'], 7: ['JUL'],
              8: ['AGUST', 'AGS', 'AUG', 'AGT'], 9: ['SEP'], 10: ['OKT', 'OCT'], 11: ['NOV', 'NOP'], 12: ['DES', 'DEC']}


def tab_of(name):
    u = name.upper()
    if any(x in u for x in ('KRWG', 'KARAWANG', 'CIKARANG', 'CKR')):
        return 'WH'
    if any(x in u for x in ('SBY', 'SURABAYA')):
        return 'SBY'
    if any(x in u for x in ('SMRG', 'SEMARANG', 'SMG')):
        return 'SMG'
    if any(x in u for x in ('HQ', 'JKT', 'JAKARTA', 'PUSAT')):
        return 'HQ'
    return None


# ───────────────────────── extract ─────────────────────────
def cmd_extract(a):
    raw = json.load(open(a.raw_json, encoding='utf-8'))['raw']
    try:
        b = base64.urlsafe_b64decode(raw + '=' * (-len(raw) % 4))
        if b'Received' not in b[:8000] and b'From' not in b[:8000]:
            raise ValueError
    except Exception:
        b = raw.encode('utf-8', 'surrogateescape')
    msg = email.message_from_bytes(b, policy=policy.default)
    os.makedirs(a.outdir, exist_ok=True)
    files = []
    for p in msg.walk():
        fn = p.get_filename()
        if not fn or fn.lower().endswith(('.png', '.jpg', '.jpeg', '.gif')):
            continue
        data = p.get_payload(decode=True)
        safe = os.path.basename(fn).replace('\r', '').replace('\n', '')
        with open(os.path.join(a.outdir, safe), 'wb') as f:
            f.write(data)
        files.append({'name': safe, 'bytes': len(data)})
    print(json.dumps({'subject': str(msg['Subject']), 'date': str(msg['Date']), 'from': str(msg['From']),
                      'files': files}, ensure_ascii=False, indent=1))


# ───────────────────────── xls 파서 ─────────────────────────
def norm(v):
    return re.sub(r'\s+', ' ', str(v)).strip().upper()


def find_hdr(sh, *labels, startswith=False, maxrow=15):
    for r in range(min(sh.nrows, maxrow)):
        for c in range(sh.ncols):
            v = norm(sh.cell_value(r, c))
            for lab in labels:
                if v == lab or (startswith and v.startswith(lab)):
                    return r, c
    return None


def cell_text(v):
    if isinstance(v, float):
        return str(int(v)) if v == int(v) else str(v)
    return str(v).strip()


def xl_date(v, datemode):
    import xlrd
    if isinstance(v, float) and v > 0:
        try:
            return xlrd.xldate_as_datetime(v, datemode).date().isoformat()
        except Exception:
            return None
    s = str(v).strip()
    for fmt in ('%d/%m/%Y', '%d-%m-%Y', '%Y-%m-%d', '%d %b %Y', '%d-%b-%y', '%d-%b-%Y'):
        try:
            return dt.datetime.strptime(s, fmt).date().isoformat()
        except Exception:
            pass
    return None


REKAP_COLS = {  # staff_payroll 컬럼 ← Rekap Gaji 헤더
    'gaji_pokok': 'GAJI', 'tunj_jabatan': 'TUNJANGAN JABATAN', 'total_tunj_tetap': 'TOTAL TJ.TETAP',
    'total_tunj_tidak_tetap': 'TOTAL TJ.TIDAK TETAP', 'total_bpjs_perusahaan': 'TOTAL BPJS TANGGUNGAN PERUSAHAAN',
    'total_gaji_gross': 'TOTAL GAJI GROSS', 'total_potongan': 'TOTAL POTONGAN KARYAWAN', 'take_home_pay': 'TOTAL',
}


def parse_rekap(path):
    """Rekap Gaji 워크북 → {tab: {...집계..., 'rows': [개인행]}}"""
    import xlrd
    wb = xlrd.open_workbook(path)
    out = {}
    for sh in wb.sheets():
        t = tab_of(sh.name)
        hg = find_hdr(sh, 'TOTAL GAJI GROSS')
        hs = find_hdr(sh, 'SECTION (DIVISI)', 'SECTION')
        hn = find_hdr(sh, 'NIK')
        if not (t and hg and hs and hn):
            continue
        hr = hg[0]
        col = {}
        for c in range(sh.ncols):
            col.setdefault(norm(sh.cell_value(hr, c)), c)

        def c_of(label):
            return col.get(label)

        title = ' '.join(norm(sh.cell_value(r, 0)) for r in range(min(5, sh.nrows)))
        m = re.search(r'BULAN\s+([A-Z]+)\s+(\d{4})', title)
        period = '%s-%02d' % (m.group(2), BULAN[m.group(1)]) if m and m.group(1) in BULAN else None
        rows, sec, gross, gt = [], {}, 0.0, None
        for r in range(hr + 1, sh.nrows):
            nik = cell_text(sh.cell_value(r, hn[1]))
            g = sh.cell_value(r, hg[1])
            if nik.upper().startswith('GRAND TOTAL'):
                gt = g if isinstance(g, float) else None
                continue
            if not nik or not isinstance(g, float):
                continue
            s = norm(sh.cell_value(r, hs[1]))
            sec[s] = sec.get(s, 0) + 1
            gross += g

            def val(label):
                c = c_of(label)
                v = sh.cell_value(r, c) if c is not None else ''
                return v

            def num(label):
                v = val(label)
                return round(v) if isinstance(v, float) else None

            ter = val('TER')
            rows.append({
                'nik': nik, 'name': str(val('NAMA PEGAWAI')).strip(), 'npwp': cell_text(val('NPWP')) or None,
                'no_rek': cell_text(val('NO REK BANK')) or None, 'kode_ter': cell_text(val('KODE TER')) or None,
                'ter_pct': ter if isinstance(ter, float) else None,
                'ptkp': cell_text(val('STATUS PTKP')) or None, 'section': str(val('SECTION (DIVISI)') or val('SECTION')).strip() or None,
                'grade': cell_text(val('GRADE')) or None, 'position': str(val('JABATAN')).strip() or None,
                'birth': xl_date(val('TGL LAHIR'), wb.datemode), 'join': xl_date(val('TGL JOIN'), wb.datemode),
                'location': TAB_LOCATION[t],
                **{k: num(v) for k, v in REKAP_COLS.items()},
            })
        out[t] = {'sheet': sh.name, 'period': period, 'sections': sec, 'hc': len(rows), 'gross': round(gross),
                  'grand_total': round(gt) if gt is not None else None, 'rows': rows}
    return out


def pick_sheet(wb, month):
    """여러 달 시트가 누적된 파일(Kompensasi 등)에서 해당 월 시트 선택. 없으면 마지막 시트."""
    toks = MON_TOKENS.get(month, [])
    hits = [sh for sh in wb.sheets() if any(re.search(r'\b%s' % t, sh.name.upper()) for t in toks)]
    return (hits or wb.sheets())[-1]


def sum_col(path, month, *labels, startswith=False):
    import xlrd
    wb = xlrd.open_workbook(path)
    sh = pick_sheet(wb, month)
    h = find_hdr(sh, *labels, startswith=startswith)
    n = find_hdr(sh, 'NIK')
    if not (h and n):
        return None, sh.name
    tot = 0.0
    for r in range(h[0] + 1, sh.nrows):
        nik = cell_text(sh.cell_value(r, n[1]))
        v = sh.cell_value(r, h[1])
        if nik and not nik.upper().startswith(('GRAND', 'TOTAL')) and isinstance(v, float):
            tot += v
    return round(tot), sh.name


def parse_checklist(path, period):
    """Salary Check List '직전3개월' 시트의 당월 열 → {'orang': {total,HQ,Cabang}, 'salary':…, 'thr':…, 'bonus':…, 'kompensasi':…}"""
    import openpyxl
    wb = openpyxl.load_workbook(path, data_only=True, read_only=True)
    ws = wb.worksheets[0]
    rows = [list(r) for r in ws.iter_rows(min_row=1, max_row=45, values_only=True)]

    def numv(x):
        try:
            return round(float(str(x).replace(',', '')))
        except Exception:
            return None

    cur = None
    for r in rows[:8]:
        for j, x in enumerate(r):
            if x is not None and '당월' in str(x):
                cur = j
    year = period[:4]
    hdr_label = None
    for r in rows[:8]:
        for j, x in enumerate(r):
            if x is not None and year in str(x) and (cur is None or j == cur):
                cur, hdr_label = j, str(x).strip()
    if cur is None:
        return None
    keys = {'A)': 'orang', 'B)': 'salary', 'C)': 'thr', 'E)': 'bonus', 'F)': 'kompensasi'}
    out, k = {'_month_label': hdr_label}, None
    for r in rows:
        lab = next((str(x).strip() for x in r[:3] if x is not None and re.match(r'^[A-I]\)', str(x).strip())), None)
        if lab:
            k = keys.get(lab[:2])
            if k:
                out[k] = {'total': numv(r[cur])}
            continue
        if k and len(r) > 2 and r[2] is not None:
            s = str(r[2])
            if 'HQ' in s:
                out[k]['HQ'] = numv(r[cur])
            elif 'Cabang' in s:
                out[k]['Cabang'] = numv(r[cur])
    return out


# ───────────────────────── 집계 ─────────────────────────
def strip_rev(fn):
    return re.sub(r'^\s*REV(ISI)?\.?\s*', '', fn, flags=re.I)


def collect(dirs, period):
    month = int(period[5:7])
    data = {'tabs': {}, 'kompensasi': {}, 'insentif': {}, 'checklist': None, 'unclassified': [], 'sources': [], 'thr_files': []}
    for d in dirs:
        for f in sorted(os.listdir(d)):
            p = os.path.join(d, f)
            u = strip_rev(f).upper()
            if not os.path.isfile(p):
                continue
            if u.startswith('REKAP GAJI') and u.endswith('.XLS') and 'THR' not in u:
                parsed = parse_rekap(p)
                data['tabs'].update(parsed)       # 뒤 폴더(수정본)가 해당 탭만 덮어씀
                data['sources'].append({'file': f, 'tabs': sorted(parsed)})
            elif 'KOMPENSASI' in u and u.endswith('.XLS'):
                v, shn = sum_col(p, month, 'KOMPENSASI SEBELUM PPH')
                t = tab_of(f)
                if v is None or t is None:
                    data['unclassified'].append(f)
                else:
                    data['kompensasi'][t] = v
                    data['sources'].append({'file': f, 'tab': t, 'sheet': shn})
            elif u.startswith(('INSENTIVE SALES', 'INSENTIF SALES')) and u.endswith('.XLS'):
                v, shn = sum_col(p, month, 'NILAI INSENTIF', startswith=True)
                t = tab_of(f)
                if v is None or t is None:
                    data['unclassified'].append(f)
                else:
                    data['insentif'][t] = data['insentif'].get(t, 0) + v
                    data['sources'].append({'file': f, 'tab': t, 'sheet': shn})
            elif 'SALARY CHECK LIST 3 MONTH' in u and u.endswith('.XLSX'):
                data['checklist'] = parse_checklist(p, period)
                data['sources'].append({'file': f, 'role': 'checklist'})
            elif 'THR' in u:
                data['thr_files'].append(f)
            elif u.startswith(('(GROSS)NEW A_SALARY CHECK LIST', 'LAPOR BULAAN GAJI', 'LAPOR BULANAN GAJI')):
                pass                                # 참고용(반영 대상 아님)
            else:
                data['unclassified'].append(f)
    return data


def juta(v):
    return round(v / 1e6 + 1e-9, 1)


def build(data, period, overrides):
    errs, warns = [], []
    tabs = data['tabs']
    for t in TABS:
        if t not in tabs:
            errs.append('Rekap Gaji 시트 누락 : %s' % t)
    if errs:
        return None, errs, warns
    for t in TABS:
        x = tabs[t]
        if x['period'] != period:
            errs.append('%s 시트 기간 불일치 : 시트=%s, 지정=%s' % (t, x['period'], period))
        if x['grand_total'] is None or abs(x['grand_total'] - x['gross']) > 1:
            errs.append('%s 개인행 합계(%s) ≠ Grand Total(%s)' % (t, x['gross'], x['grand_total']))
        if sum(x['sections'].values()) != x['hc']:
            errs.append('%s Section 인원 합 ≠ 인원' % t)
    niks = [r['nik'] for t in TABS for r in tabs[t]['rows']]
    if len(niks) != len(set(niks)):
        errs.append('NIK 중복 존재(시트 간 중복 포함)')
    hc = {t: tabs[t]['hc'] for t in TABS}
    gross = {t: tabs[t]['gross'] for t in TABS}
    komp = {t: data['kompensasi'].get(t, 0) for t in TABS}
    ins = {t: data['insentif'].get(t, 0) for t in TABS}
    thr = {t: 0 for t in TABS}
    for k, v in overrides.items():      # 예: thr.HQ=268.9 (Juta) — 수기 산출값 주입
        item, t = k.split('.')
        {'thr': thr, 'insentif': ins, 'kompensasi': komp}[item][t] = round(float(v) * 1e6)
    if data['thr_files'] and not any(thr.values()):
        errs.append('THR 파일 존재하나 THR 값 미지정(--override thr.<TAB>=<Juta>) : %s' % data['thr_files'])
    cl = data['checklist']
    if not cl:
        errs.append('Salary Check List 3 Month Report 누락 또는 당월 열 식별 실패 → 대조 검증 불가')
    else:
        cab = lambda d: sum(d[t] for t in ('WH', 'SBY', 'SMG'))

        def cmp(name, key, d, tol, blocking=True):
            c = cl.get(key)
            if not c:
                (errs if blocking else warns).append('Check List %s 행 없음' % name)
                return
            for lab, mine in (('total', sum(d.values())), ('HQ', d['HQ']), ('Cabang', cab(d))):
                ref = c.get(lab)
                if ref is None or abs(ref - mine) > tol:
                    (errs if blocking else warns).append('%s %s 불일치 : 집계=%s, Check List=%s' % (name, lab, mine, ref))

        cmp('인원', 'orang', hc, 0)
        cmp('인건비(Salary)', 'salary', gross, 2)
        cmp('보상비(Kompensasi PKWT)', 'kompensasi', komp, 2)
        c_thr = (cl.get('thr') or {}).get('total') or 0
        if abs(c_thr - sum(thr.values())) > 2:
            errs.append('THR 불일치 : 집계=%s, Check List=%s' % (sum(thr.values()), c_thr))
        c_bon = (cl.get('bonus') or {}).get('total') or 0
        if abs(c_bon - sum(ins.values())) > 2:
            warns.append('상여(Bonus/Insentif) Check List=%s vs Insentive Sales 집계=%s (Check List E행은 양식 오류 사례 있어 경고 처리)'
                         % (c_bon, sum(ins.values())))
    if data['unclassified']:
        warns.append('미분류 첨부(반영 제외) : %s' % data['unclassified'])
    res = {'period': period, 'tabs': {}, 'company': {}}
    for t in TABS:
        res['tabs'][t] = {'sections': tabs[t]['sections'], 'total': hc[t], 'salary': juta(gross[t]),
                          'avgcost': juta(gross[t] / hc[t]) if hc[t] else 0.0,
                          'kompensasi': juta(komp[t]), 'thr': juta(thr[t]), 'insentif': juta(ins[t])}
    tg, th = sum(gross.values()), sum(hc.values())
    res['company'] = {'rows': hc, 'total': th, 'salary': juta(tg), 'avgcost': juta(tg / th),
                      'kompensasi': juta(sum(komp.values())), 'thr': juta(sum(thr.values())), 'insentif': juta(sum(ins.values()))}
    res['raw_idr'] = {'gross': gross, 'kompensasi': komp, 'thr': thr, 'insentif': ins}
    return res, errs, warns


# ───────────────────────── payrollMonthly.ts 갱신 ─────────────────────────
def fmt_num(v, one_dec=False):
    if one_dec:
        return '%.1f' % v
    return str(int(v)) if float(v) == int(v) else ('%.1f' % v)


def set_series(line, value, idx, arr_one_dec=False, avg_one_dec=True):
    m = re.search(r'm2026:\s*\[([^\]]*)\]', line)
    arr = [float(x) for x in m.group(1).split(',') if x.strip()]
    if len(arr) < idx:
        raise ValueError('이전 월 누락(m2026 길이 %d, 반영 월 index %d)' % (len(arr), idx))
    if len(arr) == idx:
        arr.append(float(value))
    else:
        arr[idx] = float(value)
    avg = round(sum(arr) / len(arr) + 1e-9, 1)
    line = line[:m.start()] + 'm2026: [' + ', '.join(fmt_num(x, arr_one_dec) for x in arr) + ']' + line[m.end():]
    return re.sub(r'avg2026:\s*[-\d.]+', 'avg2026: ' + fmt_num(avg, avg_one_dec), line)


def update_ts(ts_path, res, year_expected='2026'):
    period = res['period']
    if period[:4] != year_expected:
        raise ValueError('연도 전환(%s) — payrollMonthly.ts 가 m2026 고정 구조이므로 구조 개편 필요' % period[:4])
    idx = int(period[5:7]) - 1
    src = open(ts_path, encoding='utf-8').read().split('\n')
    cur_key, out, touched, added = None, [], 0, []
    val_for = {}
    for t in TABS:
        val_for[TAB_KEY[t]] = res['tabs'][t]
    comp = res['company']
    pending_sections = {}
    for ln in src:
        mk = re.search(r"key:\s*'([^']+)'", ln)
        if mk:
            cur_key = mk.group(1)
            if cur_key in val_for:
                pending_sections[cur_key] = dict(val_for[cur_key]['sections'])
        if cur_key and 'm2026' in ln and 'interface' not in ln and not ln.strip().startswith('//'):
            ml = re.search(r"label:\s*'([^']+)'", ln)
            mf = re.match(r'\s*(total|salary|avgcost|kompensasi|thr|insentif):', ln)
            if ml:
                label = ml.group(1)
                if cur_key == 'company':
                    t = next((k for k, v in COMPANY_ROW.items() if v == label), None)
                    if t is None:
                        raise ValueError('전사 탭 행 라벨 미인식 : %s' % label)
                    v = comp['rows'][t]
                else:
                    secname = label.split(' (')[0].strip().upper()
                    v = pending_sections[cur_key].pop(secname, 0)
                ln = set_series(ln, v, idx)
                touched += 1
            elif mf:
                f = mf.group(1)
                if f == 'total' and cur_key != 'company' and pending_sections.get(cur_key):
                    # rows 에 없는 신규 Section → total 앞에 행 추가(이전 월 0)
                    for secname, cnt in pending_sections[cur_key].items():
                        arr = [0] * idx + [cnt]
                        out.append("      { label: '%s', avg2025: 0.0, m2026: [%s], avg2026: %s },"
                                   % (secname, ', '.join(str(x) for x in arr), fmt_num(round(sum(arr) / len(arr) + 1e-9, 1), True)))
                        added.append('%s/%s' % (cur_key, secname))
                    pending_sections[cur_key] = {}
                v = (comp if cur_key == 'company' else val_for[cur_key])[f]
                ln = set_series(ln, v, idx, arr_one_dec=f in ('salary', 'avgcost'), avg_one_dec=f in ('total', 'salary', 'avgcost'))
                touched += 1
        if ln.startswith('export const PAYROLL_MONTHS_2026'):
            ln = "export const PAYROLL_MONTHS_2026 = [%s];" % ', '.join("'%d월'" % (i + 1) for i in range(max(idx + 1, len(re.findall(r"'\d+월'", ln)))))
        if ln.startswith('export const PAYROLL_UPDATED'):
            old = re.search(r"'(\d{4}-\d{2})'", ln).group(1)
            ln = "export const PAYROLL_UPDATED = '%s';   // 최신 반영월" % max(old, period)
        out.append(ln)
    text = '\n'.join(out)
    text = re.sub(r'(출처: Rekap Gaji Ascendo Internasional 월별 파일\(2025-01~)\d{4}-\d{2}', lambda m: m.group(1) + period, text)
    open(ts_path, 'w', encoding='utf-8').write(text)
    return {'series_updated': touched, 'sections_added': added}


def ts_months(ts_path):
    s = open(ts_path, encoding='utf-8').read()
    return re.search(r"PAYROLL_UPDATED = '(\d{4}-\d{2})'", s).group(1)


# ───────────────────────── payroll_monthly(DB) upsert SQL ─────────────────────────
def db_sql(res):
    """인건비 탭 SSOT(Supabase public.payroll_monthly) 반영 SQL — 집계값만(개인정보 없음). 해당 월을 통째로 교체."""
    period = res['period']
    vals = []

    def add(tab, item, row_key, v):
        vals.append("('%s','%s','%s','%s',%s)" % (tab, item, row_key.replace("'", "''"), period, fmt_num(v)))

    c = res['company']
    for t in TABS:
        add('company', 'hc', t, c['rows'][t])
    for item in ('total', 'salary', 'avgcost', 'kompensasi', 'thr', 'insentif'):
        add('company', item, '', c[item])
    for t in TABS:
        x = res['tabs'][t]
        for sec, n in sorted(x['sections'].items()):
            add(TAB_KEY[t], 'hc', sec, n)
        for item in ('total', 'salary', 'avgcost', 'kompensasi', 'thr', 'insentif'):
            add(TAB_KEY[t], item, '', x[item])
    return ("begin;\ndelete from public.payroll_monthly where period = '%s';\n"
            "insert into public.payroll_monthly (tab_key, item, row_key, period, value) values\n%s;\ncommit;"
            % (period, ',\n'.join(vals))), len(vals), round(sum(float(v.rsplit(',', 1)[1].rstrip(')')) for v in vals), 1)


# ───────────────────────── staff_payroll SQL ─────────────────────────
def q(v):
    if v is None or v == '':
        return 'null'
    if isinstance(v, (int, float)):
        return repr(v)
    return "'" + str(v).replace("'", "''") + "'"


def write_sql(path, data, period, known=None):
    rows = [r for t in TABS for r in data['tabs'][t]['rows']]
    new = [r for r in rows if known is None or r['nik'] not in known]
    L = ['-- staff / staff_private / staff_payroll %s (자동 생성 · 개인정보 포함 · 커밋 금지)' % period, 'begin;']
    if new:      # staff 마스터에 없는 NIK(신규 입사)만 등록 — staff_payroll.nik FK 선행 조건
        L.append('insert into public.staff (nik, name, location, is_active, grade, position) values')
        L.append(',\n'.join('  (%s, %s, %s, true, %s, %s)' % (q(r['nik']), q(r['name']), q(r['location']), q(r['grade']), q(r['position'])) for r in new))
        L.append('on conflict (nik) do nothing;')
        L.append('insert into public.staff_private (nik, birth_date, join_date, ptkp_status, section) values')
        L.append(',\n'.join('  (%s, %s, %s, %s, %s)' % (q(r['nik']), q(r['birth']), q(r['join']), q(r['ptkp']), q(r['section'])) for r in new))
        L.append('on conflict (nik) do nothing;')
    cols = ['nik', 'npwp', 'no_rek', 'kode_ter', 'ter_pct'] + list(REKAP_COLS) + ['periode']
    L.append('insert into public.staff_payroll (%s) values' % ', '.join(cols))
    L.append(',\n'.join('  (' + ', '.join(q(period if c == 'periode' else r[c]) for c in cols) + ')' for r in rows))
    L.append('on conflict (nik, periode) do update set ' + ', '.join('%s = excluded.%s' % (c, c) for c in cols if c not in ('nik', 'periode')) + ';')
    L.append("delete from public.staff_payroll where periode = %s and nik not in (%s);" % (q(period), ', '.join(q(r['nik']) for r in rows)))
    L.append('commit;')
    with open(path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(L) + '\n')
    import hashlib
    sig = ','.join('|'.join(str(r[c] if r[c] is not None else '') for c in ('nik', 'npwp', 'no_rek', 'kode_ter', 'total_gaji_gross', 'take_home_pay'))
                   for r in sorted(rows, key=lambda r: r['nik']))
    return {'rows': len(rows), 'new_staff': len(new), 'bytes': os.path.getsize(path),
            'sums': {k: sum((r[k] or 0) for r in rows) for k in REKAP_COLS},
            # DB 대조용: select md5(string_agg(concat_ws('|', nik, coalesce(npwp,''), coalesce(no_rek,''), coalesce(kode_ter,''),
            #   total_gaji_gross::bigint, take_home_pay::bigint), ',' order by nik collate "C")) from staff_payroll where periode = '<P>'
            'md5': hashlib.md5(sig.encode('utf-8')).hexdigest()}


def cmd_run(a):
    overrides = dict(x.split('=', 1) for x in (a.override or []))
    data = collect(a.dir, a.period)
    res, errs, warns = build(data, a.period, overrides)
    report = {'period': a.period, 'ok': not errs, 'errors': errs, 'warnings': warns, 'sources': data['sources'],
              'checklist': data['checklist'], 'result': res, 'ts_updated_before': ts_months(a.ts)}
    if res and not errs:
        sql_text, n_vals, chk = db_sql(res)
        # 검증 쿼리: select count(*), sum(value) from payroll_monthly where period = '<P>'  → rows / checksum 과 일치해야 함
        report['payroll_monthly'] = {'rows': n_vals, 'checksum': chk, 'sql': sql_text}
        if a.sql:
            known = set(open(a.staff_known, encoding='utf-8').read().replace(',', '\n').split()) if a.staff_known else None
            report['sql'] = write_sql(a.sql, data, a.period, known)
            report['sql']['path'] = a.sql
        if a.apply:
            try:
                report['ts_apply'] = update_ts(a.ts, res)
            except ValueError as e:
                report['ok'] = False
                report['errors'].append('payrollMonthly.ts 갱신 실패 : %s' % e)
    print(json.dumps(report, ensure_ascii=False, indent=1))
    sys.exit(0 if report['ok'] else 2)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sp = ap.add_subparsers(dest='cmd', required=True)
    e = sp.add_parser('extract')
    e.add_argument('raw_json')
    e.add_argument('outdir')
    e.set_defaults(fn=cmd_extract)
    r = sp.add_parser('run')
    r.add_argument('--period', required=True, help='YYYY-MM')
    r.add_argument('--dir', action='append', required=True, help='첨부 폴더(수정본 폴더는 뒤에 추가)')
    r.add_argument('--ts', default=TS_DEFAULT)
    r.add_argument('--apply', action='store_true', help='payrollMonthly.ts 갱신')
    r.add_argument('--sql', help='staff_payroll upsert SQL 출력 경로(저장소 밖)')
    r.add_argument('--staff-known', help='staff 마스터 기존 NIK 목록 파일(쉼표/줄바꿈 구분) — 지정 시 신규 NIK만 staff 등록')
    r.add_argument('--override', action='append', help='예: thr.HQ=268.9 (백만 IDR)')
    r.set_defaults(fn=cmd_run)
    a = ap.parse_args()
    a.fn(a)


if __name__ == '__main__':
    main()
