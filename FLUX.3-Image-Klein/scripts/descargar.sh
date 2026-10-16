#!/usr/bin/env bash
# Fase 1.2: descarga con commit fijado y SHA256 contra el lfs.oid de HF. Corre en ai-lab, en tmux.
set -euo pipefail

DEST=/data/ai-lab/models/flux-3-image-klein
BFL_REV=8454017f9ebaada30c998fccd9f67a80c7580f68
QWEN_REV=1cd86afb9a95c410a6038ab3b40d8b578c892266
export HF_HOME=/data/ai-lab/cache/huggingface
HF=("$HOME/.local/bin/uvx" --from huggingface_hub hf download)

mkdir -p "$DEST/te"
"${HF[@]}" black-forest-labs/flux-3-image-klein --revision "$BFL_REV" --local-dir "$DEST" \
  model.safetensors ae.safetensors config.json LICENSE.md NOTICE.md \
  variants/fp8r/model.safetensors variants/fp8r/config.json variants/fp8r/hf_quant_config.json
"${HF[@]}" Qwen/Qwen3-VL-4B-Instruct-GGUF --revision "$QWEN_REV" --local-dir "$DEST/te" \
  Qwen3VL-4B-Instruct-Q4_K_M.gguf Qwen3VL-4B-Instruct-Q8_0.gguf

cd "$DEST"
sha256sum -c <<'EOF'
c3e9813cdd049c831c836b2e9db61150e49a93fc1a4c63b256494642fee0bd7c  model.safetensors
868fe7b343cc8f3a19dbcfcafbc3d5f888802be3f89bd81b65b3621a066ce8f3  ae.safetensors
30054053f630725b488aead9a81b422793cee18027856a16bd17b902ad612018  variants/fp8r/model.safetensors
66358cb18bb6b3b1b6675aa412c7a88ef01d228f481184d13668e5201c730a0a  te/Qwen3VL-4B-Instruct-Q4_K_M.gguf
054721f478bc5fa6beffb7f38eae575d45298f88cbb8d2f83ef675a727863eb1  te/Qwen3VL-4B-Instruct-Q8_0.gguf
EOF
echo "descarga ok $(date -Is)"
