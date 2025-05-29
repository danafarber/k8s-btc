from fastapi import FastAPI
import requests
import time
from threading import Thread

app = FastAPI()

prices = []
url='https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=usd'

def fetch_prices():
    while True:
        try:
            res = requests.get(url, timeout=10)
            price = float(res.json()["bitcoin"]["usd"])
            now = time.time()

            
            prices.append((now, price))
            print(f"[{time.ctime()}] BTC Price: ${price}")

            
            ten_minutes_ago = now - 600
            while prices and prices[0][0] < ten_minutes_ago:
                prices.popleft()

            #10 min avg
            if len(prices) > 0:
                avg = sum(p for t, p in prices) / len(prices)
                print(f"[{time.ctime()}] 10-min BTC avg: ${avg:.2f}")

        except Exception as e:
            print(f"Error: {e}")

        time.sleep(60)

@app.get("/price")
def get_price():
    return {"current_btc_price": prices[-1] if prices else None}

@app.get("/avg")
def get_avg():
    if len(prices) >= 1:
        return {"10_minute_avg": sum(prices) / len(prices)}
    return {"10_minute_avg": None}


if __name__ == "__main__":
    fetch_prices()
