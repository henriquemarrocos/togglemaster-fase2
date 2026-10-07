-- APENAS PARA AMBIENTE LOCAL.
-- Pré-cadastra a chave de serviço do evaluation-service, para o compose subir
-- sem passo manual. Chave em texto plano: tm_key_local_evaluation_service_dev
-- (o banco guarda só o SHA-256, igual ao auth-service faz).
-- Na nuvem, gere uma chave real via POST /admin/keys e guarde no Secret.
INSERT INTO api_keys (name, key_hash)
VALUES ('evaluation-service-local', '62162197fd44b913e66784ae3202374b40ac7d4b6c065cffea356401dfb799df')
ON CONFLICT (key_hash) DO NOTHING;
