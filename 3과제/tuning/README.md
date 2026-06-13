# tuning/ — 부하 테스트 & 자동 튜닝 (AWS CloudShell 기준)

대회 채점 방식(가용성 / 성능효율 / 비용)과 동일하게 부하를 걸고, HPA·request 값을
**자동으로 스윕해 최적값을 찾는** 도구 모음. **AWS CloudShell**에서 바로 돌아간다.

> ⚠️ 절대값(예: `cpu 500m`)은 **앱마다 다르다**. 대회날 새 앱을 받으면 `config.env`만
> 고쳐 `autotune.sh`로 그 자리에서 최적값을 다시 찾는 게 이 도구의 목적이다.
> terraform 의 기본값은 "앱 안 타는 견고한 출발점"일 뿐, 정답이 아니다.

## 구성 파일

| 파일 | 역할 |
|---|---|
| `config.env`         | **대회날 여기만 수정** — 엔드포인트 API 목록·SLO·부하파라미터·시드 |
| `cloudshell-setup.sh`| CloudShell 부트스트랩 (hey·kubectl 설치 + kubeconfig) |
| `loadtest.sh`        | 1회 부하 + 채점식 측정 (가용성/perf/노드수) |
| `autotune.sh`        | 조합 그리드 자동 스윕 → 채점 → 우승자 적용 |
| `autotune-hc.sh`     | 힐클라이밍 정밀탐색 (노드 드레인으로 노이즈↓) |

---

## CloudShell 빠른 시작

CloudShell은 **리소스가 떠 있는 그 AWS 계정**에서 연다(콘솔 우상단 `>_` 아이콘).
크레덴셜은 자동(ambient) — **프로파일 지정 불필요**.

```bash
# 0) 도구 받기 (이 레포의 tuning 폴더)
git clone https://github.com/gmst-cc/wsi-2026-task3.git
cd wsi-2026-task3/tuning

# 1) 부트스트랩 — hey/kubectl 설치 + kubeconfig (클러스터명/리전)
./cloudshell-setup.sh wsi2026-cluster ap-northeast-2

# 1-1) 현재 셸 PATH 적용 (직접 kubectl/hey 칠 때 필요. 새 세션은 자동)
export PATH="$HOME/bin:$PATH"

# 2) 클러스터 보이는지 확인
kubectl -n app get pods

# 3) 엔드포인트 확인 (terraform output 또는 CloudFront 콘솔)
#    예: http://dj1k92w9552mb.cloudfront.net

# 4) baseline 측정
./loadtest.sh http://<endpoint> 180s baseline

# 5) 최적값 자동 탐색
./autotune.sh http://<endpoint> 90s
```

### hey 설치 실패 시 (loadtest가 전부 `NO DATA`)
`cloudshell-setup.sh`는 hey를 공식 S3 미러에서 받는데, 이 미러가 **403(AccessDenied)** 를
내면 깨진 파일(에러 XML)이 `~/bin/hey`로 저장돼 실행이 안 되고 측정이 `NO DATA`로 나온다.
확인·복구:

```bash
# 진단: 깨졌으면 XML/200바이트 내외 + 실행 시 'syntax error near ... <?xml'
hey -h 2>&1 | head -1
head -c 200 ~/bin/hey

# 복구: hey를 Go로 직접 빌드 (다른 도구로 바꾸는 게 아니라 hey 그대로)
sudo dnf install -y golang
GOPATH=/tmp/go GOCACHE=/tmp/gocache GOBIN="$HOME/bin" go install github.com/rakyll/hey@latest
hey -h | head -1     # usage 뜨면 정상
```
> 빌드 캐시는 `/tmp`(overlay, 넉넉)로 빼 1GB 홈을 안 쓴다. S3 미러가 복구되면 위 과정 불필요.

> CloudShell은 홈(`~`) 1GB만 영속이고 컴퓨트는 세션 종료 시 초기화된다.
> `~/bin`(설치물)과 `~/.kube/config`는 남고, `/tmp`의 결과 CSV는 세션 한정.

### CloudShell이 아닌 환경
- **macOS**: `brew install hey kubectl awscli python3`
- **Linux**: `cloudshell-setup.sh`가 그대로 동작(Amazon Linux/Ubuntu 공통, `~/bin` 설치).
- **Windows**: WSL2 우분투에서 Linux와 동일하게.
- CloudShell이 아니면 본인 계정 자격증명이 필요(`aws configure` 또는 프로파일).
  이 프로젝트의 리소스 생성은 **`lee` 프로파일** 전제 — 단, CloudShell은 ambient라 불필요.

---

## config.env — 대회날 채우는 곳

```bash
APIS=(
  # name | slo_sec | conc | qps | METHOD | path(쿼리포함) | json_body(POST만)
  "user|0.2|30|10|GET|/v1/user?email=loadseed1@example.org&...|"
  "product|0.2|30|10|GET|/v1/product?id=loadseedp1&...|"
  "stress|1.0|12|2|POST|/v1/stress|{...json...}"
)
SEEDS=( "POST|/v1/user|{...}" "POST|/v1/product|{...}" )  # GET 부하가 맞힐 행 미리 삽입
AVAIL_GATE=99      # 가용성 합격선(%); 미만이면 autotune 점수 실격
COST_PENALTY=6     # 노드 평균 1대 초과당 감점
NS=app             # k8s 네임스페이스
```
- `name`은 **같은 이름의 Deployment**를 autotune이 튜닝한다(앱 이름 = Deployment 이름 전제).
- `slo_sec`는 채점기준표의 성능 기준을 그대로 넣는다.

---

## loadtest.sh

```bash
./loadtest.sh <endpoint> [duration] [label]
```
config의 모든 API에 동시에 부하 → 출력:

```
=== baseline ===
api             n  avail%  perf%     p50     p95     p99     max
user         5400  100.0%  99.6%   0.041   0.058   0.071   0.210
product      5400  100.0%  99.7%   0.039   0.056   0.069   0.198
stress        720  100.0%  81.6%   0.630   0.940   0.980   1.120
nodes      min=2 max=6 avg=3.40  (cost proxy avg/2 = 1.70)
```
- `perf%`↑ = 성능점수↑, `nodes avg`↓ = 비용점수↑ (트레이드오프).
- 산출물: `/tmp/tune-<label>/{<api>.csv, nodes.csv}`.

## autotune.sh — 그리드 자동 스윕

```bash
./autotune.sh <endpoint> [duration]
```
- config의 모든 앱에 **균일한 (cpu·util·min·max)** 조합을 차례로 적용(live `kubectl patch`, terraform 재apply 없음).
- 조합당: patch → rollout → 45s 안정화 → loadtest → 채점.
- 점수 = `평균 perf% − 노드비용패널티 − (가용성<GATE면 실격)`.
- 끝나면 **우승 조합을 클러스터에 적용**하고 terraform 반영값을 출력.
- 조합은 스크립트 상단 `COMBOS`에서 추가/수정.

## autotune-hc.sh — 힐클라이밍 정밀탐색

```bash
./autotune-hc.sh <endpoint> [duration] [start_cpu] [start_util] [max_moves]
```
- 시작점에서 cpu(±100m)·util(±5)을 흔들어 점수 개선 방향으로 이동(first-improvement).
- 매 trial 전 **노드를 baseline까지 드레인**(Karpenter consolidation 대기) → 비용 측정 노이즈↓.
- `autotune.sh`로 대략 우승 영역 찾은 뒤, 그 근처를 정밀화할 때 사용.

---

## 대회날 워크플로 (요약)

1. 리소스 띄운 계정에서 **CloudShell** 열기 → `git clone` → `cd tuning`.
2. `./cloudshell-setup.sh <cluster> <region>`.
3. 받은 앱·채점기준표 보고 **`config.env`의 APIS/SEEDS/SLO 수정**.
4. `./loadtest.sh <ep> 180s baseline`로 현재 상태 확인.
5. `./autotune.sh <ep> 90s`로 최적 조합 선정 → 필요하면 `autotune-hc.sh`로 정밀화.
6. 출력된 값으로 `terraform/k8s_apps.tf` 수정 후 `terraform apply` (영구 반영).

> 부하는 Karpenter 노드를 띄워 **비용 발생**. 끝나면 consolidation(~60s) 확인,
> 종료 시 `terraform destroy`.
