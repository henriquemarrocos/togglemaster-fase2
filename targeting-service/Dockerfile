# ---------- Estágio 1: build (instala dependências) ----------
FROM python:3.11-slim AS builder

WORKDIR /app

# Só o requirements primeiro para aproveitar o cache de camadas
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ---------- Estágio 2: runtime ----------
FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PORT=8003

WORKDIR /app

COPY --from=builder /install /usr/local

RUN useradd --create-home --uid 10001 appuser
COPY --chown=appuser:appuser app.py .
USER appuser

EXPOSE 8003

# Workers síncronos SEM threads: o SimpleConnectionPool do psycopg2 não é
# thread-safe. Concorrência vem de processos (cada um com pool de até 5
# conexões → 2 workers = até 10 conexões por pod no RDS).
CMD ["sh", "-c", "exec gunicorn --bind 0.0.0.0:${PORT} --workers 2 --timeout 30 app:app"]
