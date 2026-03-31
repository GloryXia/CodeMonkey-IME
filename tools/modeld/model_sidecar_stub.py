#!/usr/bin/env python3
"""本地模型 sidecar stub。

只返回启发式上下文分数，用于验证 Phase 1 的桥接、缓存和回退链路。
"""

from __future__ import annotations

import argparse
import json
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


TECH_TOKENS = {
    "api",
    "bug",
    "ci",
    "config",
    "curl",
    "dev",
    "fix",
    "git",
    "http",
    "https",
    "json",
    "log",
    "merge",
    "npm",
    "pr",
    "python",
    "release",
    "script",
    "sql",
    "token",
}

URL_SCHEMES = {
    "file",
    "ftp",
    "http",
    "https",
    "mailto",
    "obsidian",
    "raycast",
    "smb",
    "vscode",
}


def contains_cjk(text: str) -> bool:
    return bool(re.search(r"[\u4e00-\u9fff]", text or ""))


def contains_ascii_word(text: str) -> bool:
    return bool(re.search(r"[A-Za-z]", text or ""))


def detect_tech_hint(text: str) -> bool:
    lowered = (text or "").lower()
    if any(token in lowered for token in TECH_TOKENS):
        return True
    return bool(re.search(r"[A-Za-z]+[_/-][A-Za-z0-9_/-]+", text or ""))


def detect_protocol_hint(last_commit_text: str, target_punct: str) -> bool:
    if target_punct != ":":
        return False
    normalized = (last_commit_text or "").strip().lower()
    return normalized in URL_SCHEMES


def classify_context(
    recent_committed: str,
    last_commit_text: str,
    current_input: str,
    target_punct: str = "",
) -> tuple[str, float, dict]:
    combined = " ".join(part for part in [recent_committed, last_commit_text, current_input] if part)
    zh = contains_cjk(combined)
    en = contains_ascii_word(combined)
    tech = detect_tech_hint(combined)

    if zh and en:
        context = "tech_mixed" if tech else "mixed"
    elif zh:
        context = "zh_text"
    elif en:
        context = "en_text"
    else:
        context = "neutral"

    scores = {
        "zh_prob": 0.1,
        "en_prob": 0.1,
        "tech_prob": 0.05,
        "zh_punct_prob": 0.2,
        "en_punct_prob": 0.8,
        "space_before_en_prob": 0.4,
    }

    if detect_protocol_hint(last_commit_text, target_punct):
        scores.update({
            "zh_prob": 0.18,
            "en_prob": 0.82,
            "tech_prob": 0.91,
            "zh_punct_prob": 0.04,
            "en_punct_prob": 0.96,
            "space_before_en_prob": 0.28,
        })
        return "protocol_hint", 0.95, scores

    if context == "zh_text":
        scores.update({
            "zh_prob": 0.92,
            "en_prob": 0.08,
            "zh_punct_prob": 0.92,
            "en_punct_prob": 0.08,
            "space_before_en_prob": 0.74,
        })
        confidence = 0.88
    elif context == "en_text":
        scores.update({
            "zh_prob": 0.07,
            "en_prob": 0.93,
            "zh_punct_prob": 0.12,
            "en_punct_prob": 0.88,
            "space_before_en_prob": 0.16,
        })
        confidence = 0.86
    elif context in {"mixed", "tech_mixed"}:
        scores.update({
            "zh_prob": 0.38,
            "en_prob": 0.47,
            "tech_prob": 0.84 if tech else 0.51,
            "zh_punct_prob": 0.76 if zh else 0.32,
            "en_punct_prob": 0.24 if zh else 0.68,
            "space_before_en_prob": 0.81,
        })
        confidence = 0.82 if tech else 0.72
    else:
        confidence = 0.55

    return context, confidence, scores


def candidate_score(context: str, candidate: dict, current_input: str) -> float:
    text = candidate.get("text", "")
    cand_type = candidate.get("type", "")
    quality = float(candidate.get("quality", 0) or 0)
    score = quality

    if context == "zh_text":
        if cand_type == "zh":
            score += 0.55
        elif cand_type == "tech":
            score += 0.22
        elif cand_type == "en":
            score -= 0.18
    elif context == "en_text":
        if cand_type == "en":
            score += 0.55
        elif cand_type == "tech":
            score += 0.28
        elif cand_type == "zh":
            score -= 0.18
    elif context in {"mixed", "tech_mixed"}:
        if cand_type == "tech":
            score += 0.42
        elif cand_type == "en":
            score += 0.24
        elif cand_type == "zh":
            score += 0.08

    if current_input and text.lower() == current_input.lower():
        score += 0.12

    return round(score, 4)


def rerank_candidates(payload: dict) -> tuple[float, list[dict]]:
    context, confidence, _ = classify_context(
        recent_committed=payload.get("recent_committed", ""),
        last_commit_text=payload.get("last_commit_text", ""),
        current_input=payload.get("current_input", ""),
        target_punct=payload.get("target_punct", ""),
    )
    current_input = payload.get("current_input", "")
    recent_committed = payload.get("recent_committed", "")
    candidates = payload.get("candidates", []) or []
    has_zh = any((candidate.get("type") == "zh") for candidate in candidates)
    has_en = any((candidate.get("type") in {"en", "tech", "mixed"}) for candidate in candidates)

    if has_zh and has_en and contains_cjk(recent_committed):
        confidence = max(confidence, 0.86)

    ranked = []
    for candidate in candidates:
        score = candidate_score(context, candidate, current_input)
        if has_zh and has_en and contains_cjk(recent_committed):
            if candidate.get("type") in {"en", "tech", "mixed"} and candidate.get("text", "").lower() == current_input.lower():
                score += 1.0
        ranked.append({
            "id": candidate.get("id", ""),
            "score": round(score, 4),
        })
    return confidence, ranked


class StubHandler(BaseHTTPRequestHandler):
    server_version = "HybridIMEModelStub/0.1"

    def _write_json(self, payload: dict, status: int = 200) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        if self.path != "/health":
            self._write_json({"error": "not_found"}, 404)
            return

        self._write_json({
            "status": "ok",
            "service": "hybrid-ime-model-stub",
        })

    def do_POST(self) -> None:
        if self.path != "/score_context":
            self._write_json({"error": "not_found"}, 404)
            return

        try:
            content_length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(content_length) or b"{}")
        except Exception as exc:  # pragma: no cover - defensive path
            self._write_json({"error": f"invalid_json:{exc}"}, 400)
            return

        request_id = payload.get("request_id", "")
        mode = payload.get("mode", "context_score")
        recent_committed = payload.get("recent_committed", "")
        last_commit_text = payload.get("last_commit_text", "")
        current_input = payload.get("current_input", "")
        target_punct = payload.get("target_punct", "")

        if mode == "candidate_rerank":
            confidence, ranked_scores = rerank_candidates(payload)
            self._write_json({
                "request_id": request_id,
                "source": "sidecar_stub",
                "confidence": confidence,
                "ranked_scores": ranked_scores,
                "ttl_ms": 800,
            })
            return

        context, confidence, scores = classify_context(
            recent_committed=recent_committed,
            last_commit_text=last_commit_text,
            current_input=current_input,
            target_punct=target_punct,
        )

        self._write_json({
            "request_id": request_id,
            "source": "sidecar_stub",
            "context": context,
            "confidence": confidence,
            "scores": scores,
            "ttl_ms": 800,
        })

    def log_message(self, format: str, *args) -> None:  # noqa: A003
        return


def main() -> None:
    parser = argparse.ArgumentParser(description="Hybrid IME local model stub")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=39571)
    args = parser.parse_args()

    server = ThreadingHTTPServer((args.host, args.port), StubHandler)
    print(f"hybrid-ime model stub listening on http://{args.host}:{args.port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
