FROM python:3.12-alpine

WORKDIR /srv
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

# Single worker on purpose: the login rate limiter keeps its counters in
# process memory, and a second worker would silently halve its effectiveness.
# One operator does not need concurrency.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "6061", \
     "--workers", "1", "--proxy-headers", "--forwarded-allow-ips", "*"]
