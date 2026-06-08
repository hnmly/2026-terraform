# 이미지 크기 최소화(<8MB 압축 기준) + curl 포함
# book은 Go 정적 바이너리(x86_64)이며 수정 없이 그대로 사용한다.
FROM alpine:3.20

# 채점 시 컨테이너에 curl 요청을 수행하므로 curl 설치
RUN apk add --no-cache curl \
    && rm -rf /var/cache/apk/*

WORKDIR /app
COPY book /app/book
RUN chmod +x /app/book

EXPOSE 8080
ENTRYPOINT ["/app/book"]
