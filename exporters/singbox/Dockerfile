FROM python:3.11-alpine

# Install docker CLI (needed to tail container logs)
RUN apk add --no-cache docker-cli

WORKDIR /app
COPY main.py .

EXPOSE 9102

CMD ["python", "-u", "main.py"]
