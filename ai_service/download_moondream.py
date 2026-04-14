import os
import torch
from transformers import AutoModelForCausalLM, AutoTokenizer
from huggingface_hub import login

print("Iniciando download massivo do Moondream 3 (Pode levar de 10 a 20 minutos)...")

# Define the model ID
model_id = "moondream/moondream3-preview"

try:
    print("Baixando o modelo para o cache local do HuggingFace...")
    # This downloads and caches the model
    model = AutoModelForCausalLM.from_pretrained(
        model_id,
        trust_remote_code=True,
        dtype=torch.float16,
        # We will map to CPU first to just download it safely. On actual running, we will use CUDA
        device_map={"": "cpu"}
    )
    
    print("Baixando e compilando o Tokenizer...")
    tokenizer = AutoTokenizer.from_pretrained(
        model_id,
        trust_remote_code=True
    )
    
    print("âœ… Sucesso! O LLM Moondream 3 Preview de 2 BilhÃµes de parÃ¢metros estÃ¡ baixado localmente.")
except Exception as e:
    print(f"âŒ Erro ao baixar o modelo: {e}")
    print("Certifique-se de ter aceito os termos do moondream3-preview no HuggingFace e tente criar uma chave de acesso (Token).")
