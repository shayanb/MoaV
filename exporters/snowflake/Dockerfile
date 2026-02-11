FROM python:3.11-alpine

WORKDIR /app
COPY main.py .

EXPOSE 8080

CMD ["python", "-u", "main.py", "/var/log/snowflake/snowflake.log"]
