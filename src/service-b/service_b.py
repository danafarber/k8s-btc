from fastapi import FastAPI

app = FastAPI()

@app.get("/")
def home():
    return {"message": "Hello from Service B"}

@app.get("/status")
def status():
    return {"status": "Service B is running"}
