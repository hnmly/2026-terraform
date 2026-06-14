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

## 실행
```bash
cd 3과제/tools
python3 monitor.py                       # http://127.0.0.1:8080
# 옵션
python3 monitor.py --port 8080 --host 0.0.0.0 \
  --namespace app \
  --waf-log-group aws-waf-logs-wsi2026 --waf-region ap-northeast-2
```
> 프로젝트명을 바꿔 배포했다면(예: wsi2026b) WAF 로그그룹도 `--waf-log-group aws-waf-logs-wsi2026b` 로 맞추세요.

## 보는 방법 (중요)
- **로컬 PC(브라우저 가능)에서 실행 권장**: `aws eks update-kubeconfig ...` 로 클러스터 연결 후 `python3 monitor.py` → 브라우저로 `http://127.0.0.1:8080`.
- **AWS CloudShell은 브라우저로 localhost 접속이 안 됩니다(포트포워딩/웹 프리뷰 미지원).**
  CloudShell에서는 **터미널 출력 모드**를 쓰세요 (브라우저 불필요):
  ```bash
  python3 monitor.py --once  --since 15m                  # 1회 출력
  python3 monitor.py --watch 10 --since 15m               # 10초마다 갱신(Ctrl+C 종료)
  # 프로젝트명이 wsi2026b 면 WAF 로그그룹 지정:
  python3 monitor.py --once --waf-log-group aws-waf-logs-wsi2026b
  ```
  그래프가 있는 웹 UI가 필요하면 **kubeconfig/자격증명이 있는 로컬 PC**에서 `python3 monitor.py` 실행 후 브라우저로 `http://127.0.0.1:8080`.

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