# BloomRecipe server

FastAPI bridge that the iPhone app calls. It talks to Ollama on this PC and signs into **your** xBloom account to create recipes.

- **`llama3.2-vision`** — reads coffee-bag photos
- **`llama3.2`** — refines the brew recipe text

Pull both models.

## Start

```bash
ollama pull llama3.2
ollama pull llama3.2-vision
ollama serve
```

In another terminal:

```bash
cd server
python -m pip install -r requirements.txt
python -m uvicorn main:app --host 0.0.0.0 --port 8000
```

On the same Wi-Fi, open `http://YOUR-PC-LAN-IP:8000/health` from the iPhone Safari. Then put that base URL (no `/health`) in BloomRecipe → Settings → Server URL.

Windows firewall must allow port 8000.

## Endpoints

| Method | Path | What |
| --- | --- | --- |
| GET | `/health` | Server + Ollama status |
| POST | `/analyze` | Read bag photos via llama3.2-vision |
| POST | `/refine` | Tweak a recipe via llama3.2 |
| POST | `/xbloom/login` | Sign into your xBloom account |
| POST | `/xbloom/sync` | Create or update the recipe in the official app |
