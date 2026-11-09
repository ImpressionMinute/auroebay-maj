"""Construit l'annonce Discord à partir de version.json et l'envoie au webhook."""
import json, os, sys, urllib.request

hook = os.environ.get("DISCORD_WEBHOOK", "").strip()
if not hook.startswith("https://discord.com/api/webhooks/"):
    sys.exit("Secret DISCORD_WEBHOOK absent ou invalide.")

v = json.load(open("version.json", encoding="utf-8"))
version = v["version"]
notes = "\n".join(f"• {n}" for n in v.get("notes", [])[:8]) or "Corrections et améliorations."
raw = "https://raw.githubusercontent.com/ImpressionMinute/auroebay-maj/main"
mac = f"curl -fsSL {raw}/maj-mac.sh | bash"
win = f'powershell -ExecutionPolicy Bypass -c "[Net.ServicePointManager]::SecurityProtocol=3072;irm {raw}/maj-windows.ps1|iex"'

payload = {
    "username": "AurOEBay",
    "avatar_url": f"{raw}/icone.png",
    "content": f"@everyone 🚀 **AurOEBay {version}** est disponible !",
    "allowed_mentions": {"parse": ["everyone"]},
    "embeds": [{
        "title": f"🚀 AurOEBay {version}",
        "color": 0xFF6A2B,
        "description": f"**Nouveautés**\n{notes}"[:4000],
        "fields": [
            {"name": "🍎 Mac : ouvre Terminal, colle puis Entrée", "value": f"```\n{mac}\n```"},
            {"name": "🪟 Windows : ouvre PowerShell, colle puis Entrée", "value": f"```\n{win}\n```"},
            {"name": "👉 Dernière étape", "value": "Quitte complètement Chrome puis rouvre-le. Tes données sont gardées.\nUn souci ? Pose ta question dans #questions 💬"},
        ],
        "footer": {"text": "AurOEBay · le copilote du dropshipping eBay"},
    }],
}
req = urllib.request.Request(hook, data=json.dumps(payload).encode(), headers={"Content-Type": "application/json", "User-Agent": "AurOEBay-annonce"})
with urllib.request.urlopen(req, timeout=20) as r:
    print("Annonce envoyée", r.status)
