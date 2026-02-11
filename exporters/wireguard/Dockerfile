FROM python:3.11-alpine

# Install docker CLI (to run docker exec)
RUN apk add --no-cache docker-cli

WORKDIR /app
COPY main.py .

EXPOSE 9586

CMD ["python", "-u", "main.py"]
