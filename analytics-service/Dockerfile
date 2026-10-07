# ---------- Estágio 1: build (instala dependências) ----------
FROM python:3.11-slim AS builder

WORKDIR /app

# Copia só o requirements primeiro para aproveitar o cache de camadas
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ---------- Estágio 2: runtime ----------
FROM python:3.11-slim

# Logs aparecem imediatamente e sem arquivos .pyc
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PORT=8005

WORKDIR /app

# Dependências vindas do estágio de build
COPY --from=builder /install /usr/local

# Usuário sem privilégios
RUN useradd --create-home --uid 10001 appuser
COPY --chown=appuser:appuser app.py .
USER appuser

EXPOSE 8005

# 1 worker = 1 consumidor SQS por pod (a escala fica a cargo do HPA)
CMD ["sh", "-c", "exec gunicorn --bind 0.0.0.0:${PORT} --workers 1 --threads 2 app:app"]
