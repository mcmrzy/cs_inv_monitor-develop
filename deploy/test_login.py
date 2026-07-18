import urllib.request
import json

data = json.dumps({"account": "13800138000", "password": "CHANGE_ME_JENKINS_PASSWORD"}).encode()
req = urllib.request.Request(
    "http://localhost:3000/api/v1/auth/login",
    data=data,
    headers={"Content-Type": "application/json"}
)
try:
    resp = urllib.request.urlopen(req)
    print(resp.read().decode())
except Exception as e:
    print(e)
    if hasattr(e, 'read'):
        print(e.read().decode())
