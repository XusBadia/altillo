"""Runs INSIDE the Home Assistant container (aiohttp is available there).
Reads the short-lived access token from $HA_ACCESS_TOKEN and prints a long-lived one."""
import asyncio, os, sys
import aiohttp

async def main():
    async with aiohttp.ClientSession() as s:
        async with s.ws_connect("http://127.0.0.1:8123/api/websocket") as ws:
            await ws.receive_json()  # auth_required
            await ws.send_json({"type": "auth", "access_token": os.environ["HA_ACCESS_TOKEN"]})
            msg = await ws.receive_json()
            if msg.get("type") != "auth_ok":
                sys.exit(f"auth failed: {msg}")
            await ws.send_json({"id": 1, "type": "auth/long_lived_access_token",
                                "client_name": "Altillo home lab", "lifespan": 3650})
            msg = await ws.receive_json()
            if not msg.get("success"):
                sys.exit(f"token request failed: {msg}")
            print(msg["result"])

asyncio.run(main())
