# Terraform 사용법

## 사전 준비

terraform 폴더에 아래 파일/폴더를 복사:

```
terraform/
├── static/
│   ├── index.html      ← 지급파일에서 복사
│   └── main.jpeg       ← 지급파일에서 복사
├── application/
│   ├── Dockerfile
│   └── book-linux-amd64_v1.0.1
├── k8s/
│   ├── namespace.yaml
│   ├── book.yaml
│   ├── ingress.yaml
│   ├── network-policy.yaml
│   ├── grafana.yaml
│   ├── grafana-values.yaml
│   └── fluentbit.yaml
└── (terraform files)
```

## 실행

```bash
terraform init
terraform apply -var="bi_number=<비번호>"
```

## 생성 후 EC2에서

```bash
bash setup.sh
```

setup.sh가 자동으로:
1. book 이미지 빌드 & ECR push
2. grafana, fluent-bit, LBC 이미지 ECR push
3. kubectl apply (namespace, book, TGB, network-policy)
4. helm install (LBC, grafana)
5. fluent-bit daemonset 배포
