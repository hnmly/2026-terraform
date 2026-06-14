#!/usr/bin/env bash
# analyze.sh - 로그 분석 래퍼 (CloudShell/Linux)
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8
exec python3 "$(dirname "$0")/log_analyzer.py" "$@"
