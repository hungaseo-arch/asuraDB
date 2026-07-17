"""PDF 텍스트 추출 격리 실행용 경량 워커 모듈.

drive_collector 는 모듈 로드 시 임베딩 모델(수백 MB)을 올린다. PDF 추출을 별도
프로세스로 돌릴 때 무거운 모듈이 재import 되지 않도록, pdfminer 만 쓰는 이 경량
모듈을 분리한다.

배경: 일부 PDF 는 pdfminer 의 레이아웃 분석(LAParams)에서 좌표 heap 비교가
O(n^2) 로 폭주해 수 시간·수 GB 를 먹고 끝나지 않는다(2026-07-16 drive 수집이
한 파일에서 4시간+ 7.4GB 로 멈춰 있던 원인). 별도 프로세스로 격리하면 상위에서
timeout 후 kill 로 확실히 회수할 수 있다(신호 방식은 C 루프를 못 끊을 수 있음).

호출 방식(드라이브 수집기): `python -m collectors.pdf_extract` 를 subprocess 로
띄우고 PDF 바이너리를 stdin 으로, 추출 텍스트를 stdout(utf-8)으로 주고받는다.
subprocess.run(timeout=...) 이 초과 시 자식을 kill → 메모리째 회수.
"""
import io
import os
import subprocess
import sys

# 0 = 전체 페이지. 타임아웃이 실질 안전장치이므로 기본은 무제한.
DEFAULT_MAXPAGES = 0

_ROOT = os.path.join(os.path.dirname(__file__), "..")


def extract_pdf_text(data: bytes, maxpages: int = DEFAULT_MAXPAGES) -> str:
    from pdfminer.high_level import extract_text_to_fp
    from pdfminer.layout import LAParams

    buf = io.BytesIO(data)
    out = io.StringIO()
    extract_text_to_fp(buf, out, laparams=LAParams(), maxpages=maxpages)
    return out.getvalue()


def extract_isolated(data: bytes, timeout: int) -> str:
    """PDF 추출을 별도 subprocess 로 격리 실행. timeout(초) 초과 시 kill 후 TimeoutError.

    임베딩 모델을 이미 올린 수집기(drive/gmail)가 폭주 PDF 한 개로 통째로 멈추는 것을
    방지한다. 자식은 이 경량 모듈만 import 하므로 모델 재로드가 없다. 호출측은
    TimeoutError/RuntimeError 를 잡아 해당 파일만 건너뛰고 다음으로 진행하면 된다.
    """
    try:
        proc = subprocess.run(
            [sys.executable, "-m", "collectors.pdf_extract"],
            input=data,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=_ROOT,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        # subprocess.run 이 자식을 kill 하고 wait 까지 마친 뒤 예외를 던진다.
        raise TimeoutError(f"PDF 추출 {timeout}s 초과 — 레이아웃 폭주 추정, 건너뜀")

    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.decode("utf-8", "replace").strip() or "pdf_extract 실패")
    return proc.stdout.decode("utf-8", "replace")


def _main() -> int:
    data = sys.stdin.buffer.read()
    try:
        text = extract_pdf_text(data)
    except Exception as e:  # noqa: BLE001
        sys.stderr.write(f"{type(e).__name__}: {e}")
        return 1
    sys.stdout.buffer.write(text.encode("utf-8", "replace"))
    return 0


if __name__ == "__main__":
    sys.exit(_main())
