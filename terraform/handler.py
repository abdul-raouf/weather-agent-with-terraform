import json
import urllib.request
import boto3
import logging
import time


logger = logging.getLogger()
logger.setLevel(logging.INFO)


REGION = "eu-central-1"
# Use an EU inference profile ID for cross-region routing; adjust to one enabled in your account.
MODEL_ID = "eu.anthropic.claude-haiku-4-5-20251001-v1:0"

bedrock = boto3.client("bedrock-runtime", region_name=REGION)

# --- the one tool Claude can choose to call ---
TOOLS = [{
    "toolSpec": {
        "name": "get_weather",
        "description": "Get the weather forecast for a city on a given date.",
        "inputSchema": {"json": {
            "type": "object",
            "properties": {
                "latitude":  {"type": "number"},
                "longitude": {"type": "number"},
            },
            "required": ["latitude", "longitude"],
        }},
    }
}]

def get_weather(latitude, longitude):
    # open-meteo: free, no API key
    url = (f"https://api.open-meteo.com/v1/forecast?latiude={latitude}"
           f"&longitude={longitude}&daily=temperature_2m_max,temperature_2m_min,"
           f"precipitation_probability_max&forecast_days=3")
    try:
        with urllib.request.urlopen(url, timeout=8) as r:
            return json.load(r)
    except Exception as e:
        log_event(event="tool_error", tool="get_weather", error=str(e))
        # hand the failure back to Claude as data, not an exception
        return {"error": f"weather lookup failed: {e}"}

def run_agent(user_text):
    messages = [{"role": "user", "content": [{"text": user_text}]}]
    start = time.time()
    turns = 0

    while True:
        turns += 1
        resp = bedrock.converse(
            modelId=MODEL_ID,
            messages=messages,
            toolConfig={"tools": TOOLS},
            system=[{"text": "You are a concise trip-briefing assistant. "
                             "Use the weather tool when a forecast would help, "
                             "then write a short, friendly briefing."}],
        )

        stop = resp["stopReason"]
        log_event(event="model_turn", turn=turns, stop_reason=stop)


        out = resp["output"]["message"]
        messages.append(out)                     # keep Claude's turn in history

        if stop != "tool_use":
            log_event(event="complete", turns=turns,
                      latency_ms=int((time.time() - start) * 1000))
            return "".join(b.get("text", "") for b in out["content"])

        # Claude asked for a tool -> execute it and feed the result back
        for block in out["content"]:
            if "toolUse" in block:
                tu = block["toolUse"]
                log_event(event = "tool_use", tool = tu["name"], input = tu["input"])
                result = get_weather(**tu["input"])
                messages.append({"role": "user", "content": [{
                    "toolResult": {
                        "toolUseId": tu["toolUseId"],
                        "content": [{"json": result}],
                    }
                }]})

def lambda_handler(event, context):
    try:
        if "body" in event:
            body = json.loads(event["body"] or "{}")
        else:
            body = event

        user_text = body.get("text", "Give me a trip briefing.")


        log_event(event="request", user_text=user_text)
        briefing = run_agent(user_text)

        return {
            "statusCode" : 200,
            "headers" : {"Content-Type" : "application/json; charset=utf-8"},
            "body" : json.dumps({"briefing" : briefing}, ensure_ascii=False),
            }
    except Exception as e:
        log_event(event="unhandled_error", error=str(e))
        return {
            "statusCode": 500,
            "headers": {"Content-Type": "application/json; charset=utf-8"},
            "body": json.dumps({"error": "internal error"}),
        }

def log_event(**kwargs):
    # one JSON line per event -> CloudWatch can filter on any field
    logger.info(json.dumps(kwargs))


if __name__ == "__main__":
    print(run_agent("I'm in Lisbon this Saturday and Sunday. Give me a weather-based briefing on what to pack."))