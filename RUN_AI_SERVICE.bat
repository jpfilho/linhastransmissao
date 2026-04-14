cd ai_service
python -m venv .venv
call .venv\Scripts\activate.bat
pip install -r requirements.txt
python -m pip install httpx openai python-dotenv pydantic uvicorn fastapi openpyxl supabase python-multipart
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
pause
