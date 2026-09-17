# Build the linux binary first:
#   GOOS=linux GOARCH=amd64 builder --config builder-config.yaml
FROM gcr.io/distroless/base-debian12
COPY dist/otelcol-streams-fanout /otelcol-streams-fanout
COPY collector.yaml /etc/otelcol/config.yaml
EXPOSE 4317 4318 13133 55679
ENTRYPOINT ["/otelcol-streams-fanout"]
CMD ["--config", "/etc/otelcol/config.yaml"]
