# Terraform 사용법

## 실행

```bash
terraform init
terraform apply --auto-approve
비번호 입력
```

## Cloudshell VPC Environment
- Name : unicorn-mark
- VPC : unicorn-vpc
- Subnet : Any Private Subnet
- Security Group : unicorn-mark-sg

### 사전준비
```bash
# 채점시 및 스크립트 실행시 필요함

export number=<비번호>
aws configure
# defaul region을 ap-northeast-2로 설정
```

### 접속 후
```bash
aws s3 cp s3://$(aws s3 ls | grep unicorn-manifest | awk '{print $3}')/ ./ --recursive && \
curl --silent --location "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp && sudo mv /tmp/eksctl /usr/local/bin && \
source apply.sh
```

apply.sh 가 자동으로:
1. book 이미지 빌드 & ECR push
2. ECR IMMUTABLE_WITH_EXCLUSION 설정
3. eksctl 클러스터 생성
4. EKS SG 허용 (CloudShell + VPC CIDR)
5. kubectl apply (namespace, SA, deployment, service, fluent-bit, fluentd)
6. EC2 Name Tag 부여
7. Pod Identity Association
8. Pod restart + ALB Target 등록
9. helm install (Prometheus + Grafana)
10. Grafana ALB Target 등록
11. IAM 권한 설정 (Node Role CW Logs + User AssumeRole)

# Grafana [수동]

## Grafana 접속

1. 브라우저를 이용해 unicorn-grafana-alb의 DNS 주소로 접속
2. 아래 정보를 통해 grafana 로그인

| Userid | Password |
| --- | --- |
| skills<비번호> | HelloKrSkills!<비번호>@ |

## Grafana Dashboard 생성

Dashboard Name : unicorn-grafana-dashboard
| Panel Name | Panel Type | PromQL |
| :--- | :--- | :--- |
| Node CPU | Time series | `100 - (avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)` |
| Node Memory | Time series | `(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100` |
| App Pod Status | Stat | `sum by (phase) ( kube_pod_status_phase{ namespace="unicorn" } )` |
| App Ready | Stat | `count( kube_pod_status_ready{ namespace="unicorn", condition="true", pod=~"unicorn-book-app.*" } == 1 )` |
| HTTP Request Duration | ? | ? |