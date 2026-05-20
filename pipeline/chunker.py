from typing import List


MAX_TOKENS = 500
OVERLAP_TOKENS = 50


def chunk_markdown(content: str) -> List[dict]:
    """헤딩 기준 분할 → 500토큰 초과 시 단락 단위 재분할"""
    import re
    chunks = []
    sections = re.split(r'\n(?=#{1,3} )', content)

    for section in sections:
        if estimate_tokens(section) <= MAX_TOKENS:
            chunks.append({"text": section.strip(), "type": "section"})
        else:
            paragraphs = section.split('\n\n')
            buffer, buf_tokens = [], 0
            for para in paragraphs:
                pt = estimate_tokens(para)
                if buf_tokens + pt > MAX_TOKENS and buffer:
                    chunks.append({"text": '\n\n'.join(buffer).strip(), "type": "paragraph"})
                    buffer = buffer[-1:]
                    buf_tokens = estimate_tokens(buffer[0]) if buffer else 0
                buffer.append(para)
                buf_tokens += pt
            if buffer:
                chunks.append({"text": '\n\n'.join(buffer).strip(), "type": "paragraph"})

    return [c for c in chunks if c["text"]]


def estimate_tokens(text: str) -> int:
    return len(text) // 4
