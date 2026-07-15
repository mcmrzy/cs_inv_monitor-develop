FROM timescale/timescaledb:2.28.2-pg18

USER root
RUN apk add --no-cache openssl

COPY deploy/postgres/tls-entrypoint.sh /usr/local/bin/tls-entrypoint.sh
RUN chmod 0755 /usr/local/bin/tls-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/tls-entrypoint.sh"]
CMD ["postgres"]
