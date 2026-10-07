# ---------- Estágio 1: build ----------
FROM golang:1.22-alpine AS builder

WORKDIR /src

# Dependências primeiro (cache de camadas). O go.sum precisa existir:
# gere com "go mod tidy" antes do build.
COPY go.mod go.sum ./
RUN go mod download

# Código-fonte
COPY . .

# Binário estático (sem libc), sem símbolos de debug (-s -w) = imagem menor
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /out/evaluation-service .

# ---------- Estágio 2: runtime ----------
# distroless/static: sem shell nem gerenciador de pacotes, já traz
# CA certificates (necessário para HTTPS com AWS) e o usuário "nonroot"
FROM gcr.io/distroless/static-debian12:nonroot

ENV PORT=8004

COPY --from=builder /out/evaluation-service /app/evaluation-service

USER nonroot:nonroot

EXPOSE 8004

# Exec form: o próprio binário lê PORT via os.Getenv, então não precisa de shell
ENTRYPOINT ["/app/evaluation-service"]
