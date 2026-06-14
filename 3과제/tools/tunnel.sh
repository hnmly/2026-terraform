#!/usr/bin/env bash
# CloudShell에서 Flask 대시보드를 브라우저로 보기: cloudflared 터널로 공개 URL 발급.
# 사용:  bash tunnel.sh            (포트 8080, ns app, waf aws-waf-logs-wsi2026b)
#        PORT=8080 NS=app WAF=aws-waf-logs-wsi2026b bash tunnel.sh
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
PORT="${PORT:-8080}"; NS="${NS:-app}"; WAF="${WAF:-aws-waf-logs-wsi2026b}"
mkdir -p "$HOME/bin"
if [ ! -x "$HOME/bin/cloudflared" ]; then
  echo "cloudflared 설치 중..."
  curl -fsSL -o "$HOME/bin/cloudflared" https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
  chmod +x "$HOME/bin/cloudflared"
fi
if ! curl -s "http://localhost:$PORT/" >/dev/null 2>&1; then
  echo "대시보드 시작 중 (포트 $PORT, ns $NS)..."
  ( cd "$HERE" && python3 dashboard.py --namespace "$NS" --port "$PORT" --waf-log-group "$WAF" >/tmp/dash.log 2>&1 & )
  sleep 4
fi
if ! curl -s "http://localhost:$PORT/" >/dev/null 2>&1; then
  echo "!! 대시보드가 안 떴습니다. 로그: cat /tmp/dash.log  (flask 없으면: pip3 install flask)"; exit 1
fi
echo "=================================================================="
echo " 아래 https://....trycloudflare.com 주소를 노트북 브라우저로 여세요"
echo " (종료: Ctrl+C)"
echo "=================================================================="
exec "$HOME/bin/cloudflared" tunnel --url "http://localhost:$PORT"