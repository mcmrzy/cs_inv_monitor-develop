FROM docker.m.daocloud.io/library/node:20.19-alpine AS builder

WORKDIR /app

COPY package*.json ./

RUN npm ci --registry=https://registry.npmjs.org

COPY . .

RUN npm run build

FROM docker.m.daocloud.io/library/alpine:3.19

RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories && \
    apk add --no-cache nginx && \
    mkdir -p /run/nginx

COPY --from=builder /app/dist /usr/share/nginx/html

COPY nginx.conf /etc/nginx/conf.d/default.conf

USER 101

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]
