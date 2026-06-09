# 최소 이미지: busybox(curl 포함) + book 바이너리. 압축 ~5MB 목표.
# book은 Go 정적 바이너리(x86_64)이며 수정 없이 그대로 사용.
FROM busybox:musl AS base

# busybox는 wget만 있고 curl이 없으므로 정적 curl 바이너리 추가
FROM alpine:3.20 AS curl-src
RUN apk add --no-cache curl

FROM base
COPY --from=curl-src /usr/bin/curl /usr/bin/curl
COPY book /app/book
RUN chmod +x /app/book
EXPOSE 8080
ENTRYPOINT ["/app/book"]
