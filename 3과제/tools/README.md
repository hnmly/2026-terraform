# 3과제 모니터링 대시보드 (`monitor.py`)

단일 파일 웹 대시보드(표준 라이브러리만, 설치 불필요). EKS 클러스터/앱/WAF 상태를
한 화면에서 보고, 4xx/5xx 오류의 **원인과 해결법**까지 자동 진단해 보여줍니다.

## 보여주는 것
- **개요**: 통과(allow)/차단(block) 합계, 2xx·4xx·5xx 합계, Pod ready/총개수, 노드 수, 앱별 요약 카드, **진단(원인·해결)**
- **앱별(user/product/stress)**: SLO 충족률·성공률·p50/p95/p99, 2xx/4xx/5xx 카운트, 경로별·에러경로, **최근 2xx / 최근 4xx / 최근 5xx 요청** 분리 표
- **Pod**: Pod별 상태/재시작/CPU·MEM/노드/오류사유(CrashLoop·OOM 등)
- **노드**: 노드 수·타입(karpenter/base)·Ready·CPU/MEM 사용률, HPA 현황
- **WAF**: 차단(403) 룰/IP/URI/메서드 + 최근 차단 (allow와 분리)
- **진단**: Pod 크래시 원인, 5xx/4xx/성능 저하 원인 + 구체적 해결 명령

## 요구사항
- `kubectl` (현재 컨텍스트가 대상 EKS) · `aws` CLI(자격증명) · `python3`
- kubeconfig: `aws eks update-kubeconfig --name <클러스터명> --region ap-northeast-2`
- 리소스 사용량(CPU/MEM)은 metrics-server 필요(이 프로젝트는 애드온으로 설치됨)

## 웹 대시보드 (`dashboard.py` · Flask · 다크 UI)

검정 테마 + 헤더에서 **시간창 1/5/10/15/20/25/30분** 선택 + 자동 갱신(5~60s).
데이터 수집은 `monitor.py` 로직을 그대로 재사용합니다.

```bash
pip3 install --user flask                 # 최초 1회 (CloudShell/로컬 공통)
cd ~/2026-terraform/3과제/tools
aws eks update-kubeconfig --name wsi2026b-cluster --region ap-northeast-2
python3 dashboard.py --namespace app --waf-log-group aws-waf-logs-wsi2026b
# → http://<host>:8080
```

### CloudShell에서 브라우저로 보려면 → 임시 터널
CloudShell은 포트 직접 접속이 안 되므로 **임시 공개 URL 터널**(cloudflared)로 봅니다:
```bash
mkdir -p ~/bin
curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o ~/bin/cloudflared && chmod +x ~/bin/cloudflared
python3 dashboard.py --namespace app --port 8080 &      # 대시보드 백그라운드 실행
~/bin/cloudflared tunnel --url http://localhost:8080    # 출력되는 https://...trycloudflare.com 을 브라우저로
```
> ⚠️ 터널 URL은 **인증이 없습니다**. 잠깐 확인용으로만 쓰고 끝나면 `cloudflared`/대시보드 모두 종료(Ctrl+C, kill). 공개 노출 주의.

로컬 PC(브라우저 가능)면 터널 없이 바로 `python3 dashboard.py` 후 `http://127.0.0.1:8080`.

> 설치 없이 쓰려면 `monitor.py`(표준 라이브러리)로 동일 데이터 확인 — 아래 참고.
## 실행 환경별 보기

> ⚠️ **AWS CloudShell은 브라우저로 localhost 포트에 접속하는 기능(포트포워딩/웹 프리뷰)이 없습니다.**
> (Cloud9과 다름) → CloudShell에서 띄운 웹서버는 브라우저로 못 봅니다.
> **CloudShell = 터미널 모드(--once/--watch)**, **그래프 웹 UI = 로컬 PC**.

### A. CloudShell — 터미널 출력 (브라우저 불필요) ← 대회 환경
```bash
cd ~/2026-terraform/3과제/tools
aws eks update-kubeconfig --name wsi2026b-cluster --region ap-northeast-2   # 최초 1회

python3 monitor.py --once   --since 15m            # 1회 스냅샷
python3 monitor.py --watch 10 --since 15m          # 10초마다 갱신 (Ctrl+C 종료)

# WAF 로깅을 켰고 프로젝트명이 wsi2026b 면 로그그룹 지정:
python3 monitor.py --watch 10 --waf-log-group aws-waf-logs-wsi2026b
```
출력 순서: 요약(allow/block·2xx/4xx/5xx·pod·node) → 앱별 카운트+최근 5xx/4xx
→ Pod(상태/재시작/CPU·MEM/사유) → 노드 → WAF → **진단(원인·해결)**.

### B. 로컬 PC — 그래프 웹 UI
브라우저가 되는 PC(노트북)에서 (aws CLI·kubectl·python3 필요):
```bash
aws eks update-kubeconfig --name wsi2026b-cluster --region ap-northeast-2
python3 monitor.py --namespace app                 # 브라우저: http://127.0.0.1:8080
```
탭: 개요 / user / product / stress / Pod / 노드 / WAF / 진단

### 공통 옵션
```
--namespace app                 대상 네임스페이스 (기본 app)
--since 15m                     조회 기간 (5m/15m/30m/1h)
--once / --watch <초>           터미널 1회 / 주기 갱신 (CloudShell)
--port 8080 --host 127.0.0.1    웹서버 (로컬 PC)
--waf-log-group / --waf-region  WAF 로그그룹/리전 (기본 aws-waf-logs-wsi2026 / ap-northeast-2)
```
## 전제 (데이터가 비어 보일 때)
1. **WAF 탭**: terraform `waf.tf` 에 **WAF 로깅이 설정돼야** 데이터가 찹니다.
   (CloudWatch 로그그룹 `aws-waf-logs-*` + `aws_wafv2_web_acl_logging_configuration`)
   설정 전엔 WAF 탭이 "로깅 미설정"으로 표시됩니다.
2. **앱 탭**: 앱이 **JSON 액세스 로그**(필드: `status/path/method/dur_ms/client_ip/ts` 중 일부)를
   stdout 으로 찍어야 요청 통계가 잡힙니다. 형식 확인:
   ```bash
   kubectl -n app logs deploy/user --tail=3
   ```
   JSON 이 아니면 파서가 `status/code`, `path/uri`, `dur_ms/latency_ms` 등 대체 키도 시도합니다.