FROM python:3.11-alpine

RUN addgroup -S moav && adduser -S moav -G moav

WORKDIR /app
COPY main.py .
RUN chown -R moav:moav /app

EXPOSE 8080

USER moav
CMD ["python", "-u", "main.py", "/var/log/snowflake/snowflake.log"]
