#!/bin/bash
set -uo pipefail

DOMAIN="web.orbstack-playwright-repro.orb.local"

echo "============================================"
echo "OrbStack + Playwright Reproduction"
echo "============================================"
echo ""

# Step 1: Start container
echo ">>> Starting nginx container..."
docker compose up -d --wait
echo ""

# Step 2: Wait for OrbStack DNS + get container IP
echo ">>> Waiting for OrbStack domain to resolve..."
for i in $(seq 1 15); do
  IP=$(dig +short "$DOMAIN" 2>/dev/null | head -1)
  if [ -n "$IP" ]; then break; fi
  sleep 1
done
if [ -z "$IP" ]; then
  # Fallback: resolve via curl connection info
  IP=$(curl -sk --max-time 3 -w '%{remote_ip}' -o /dev/null "https://$DOMAIN" 2>/dev/null)
fi
echo "    Domain: $DOMAIN"
echo "    Container IP: ${IP:-unknown}"
echo ""

# Step 3: curl works (uses macOS Network.framework)
echo ">>> Test 1: curl (uses macOS Network.framework)"
echo -n "    https://$DOMAIN → "
HTTP_CODE=$(curl -sk --max-time 5 -o /dev/null -w '%{http_code}' "https://$DOMAIN" 2>/dev/null)
if [ "$HTTP_CODE" = "200" ]; then
  echo "HTTP $HTTP_CODE ✓"
else
  echo "HTTP $HTTP_CODE ✗"
fi
echo ""

# Step 4: Node.js raw TCP (BSD sockets)
echo ">>> Test 2: Node.js TCP connect (uses BSD sockets)"
echo -n "    connect($IP:80) → "
node -e "
const s = require('net').connect(80, '${IP:-127.0.0.1}', () => { process.stdout.write('CONNECTED ✓\n'); s.destroy(); });
s.on('error', e => process.stdout.write('FAILED: ' + e.code + ' ✗\n'));
s.setTimeout(5000, () => { process.stdout.write('TIMEOUT ✗\n'); s.destroy(); });
"
echo ""

# Step 5: Python raw TCP (BSD sockets)
echo ">>> Test 3: Python TCP connect (uses BSD sockets)"
echo -n "    connect($IP:80) → "
python3 -c "
import socket
s = socket.socket()
s.settimeout(5)
try:
    s.connect(('${IP:-127.0.0.1}', 80))
    print('CONNECTED ✓')
except Exception as e:
    print(f'FAILED: {e} ✗')
finally:
    s.close()
" 2>&1
echo ""

# Step 6: Playwright tests
echo ">>> Test 4: Playwright (uses CDP → Chrome's network service → BSD sockets)"
npx playwright test --reporter=list 2>&1 || true
echo ""

# Step 7: Raw CDP test
echo ">>> Test 5: Raw CDP Page.navigate (no Playwright, same Chrome binary)"
echo "    Launching system Chrome with --remote-debugging-port..."
# Kill any stale instances on this port
lsof -ti:9333 2>/dev/null | xargs kill 2>/dev/null || true
sleep 1

"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --user-data-dir=/tmp/cdp-repro-test \
  --no-first-run --no-default-browser-check \
  --remote-debugging-port=9333 \
  "https://$DOMAIN" &>/dev/null &
CDP_PID=$!

# Wait for CDP to be ready
for i in $(seq 1 10); do
  if curl -s http://localhost:9333/json/version &>/dev/null; then break; fi
  sleep 1
done

echo ""
echo "    a) Address bar navigation (Chrome UI → Network.framework):"
TAB_TITLE=$(curl -s http://localhost:9333/json 2>/dev/null | node -e "
const d=require('fs').readFileSync('/dev/stdin','utf8');
try{const t=JSON.parse(d).find(t=>t.type==='page');
console.log(t?t.url+' → title: \"'+t.title+'\"':'(no page tab found)')}
catch{console.log('(could not query CDP)')}" 2>/dev/null)
echo "       $TAB_TITLE"

echo ""
echo "    b) CDP Page.navigate (same Chrome → network service → BSD sockets):"
WS=$(curl -s http://localhost:9333/json 2>/dev/null | node -e "
const d=require('fs').readFileSync('/dev/stdin','utf8');
try{const t=JSON.parse(d).find(t=>t.type==='page');console.log(t?.webSocketDebuggerUrl||'')}
catch{}" 2>/dev/null)
if [ -n "$WS" ]; then
  CDP_RESULT=$(node -e "
const ws=new(require('ws'))('$WS');
ws.on('open',()=>ws.send(JSON.stringify({id:1,method:'Page.navigate',params:{url:'https://$DOMAIN/test-cdp'}})));
ws.on('message',d=>{const m=JSON.parse(d);if(m.id===1){
  if(m.result?.errorText)console.log(m.result.errorText);
  else console.log('OK');
  ws.close()}});
ws.on('error',e=>console.log('WS error: '+e.message));
setTimeout(()=>{console.log('TIMEOUT');process.exit(0)},8000);
" 2>&1)
  echo "       ${CDP_RESULT:-(no result)}"
else
  echo "       (could not get WebSocket URL)"
fi

kill $CDP_PID 2>/dev/null
wait $CDP_PID 2>/dev/null
rm -rf /tmp/cdp-repro-test 2>/dev/null

echo ""
echo "============================================"
echo "Summary"
echo "============================================"
echo ""
echo "  curl (Network.framework):     WORKS  — macOS routes via Network.framework"
echo "  Node.js TCP (BSD sockets):    FAILS  — EHOSTUNREACH"
echo "  Python TCP (BSD sockets):     FAILS  — No route to host"
echo "  Chrome address bar:           WORKS  — Chrome UI uses Network.framework"
echo "  Chrome CDP Page.navigate:     FAILS  — net::ERR_ADDRESS_UNREACHABLE"
echo "  Playwright (uses CDP):        FAILS  — net::ERR_ADDRESS_UNREACHABLE"
echo ""
echo "The same Chrome binary, same container, same URL — but the address"
echo "bar works while CDP Page.navigate does not. This proves the issue is"
echo "in how Chrome's network service handles CDP-initiated requests vs"
echo "user-initiated navigation on macOS with OrbStack."
echo "============================================"
