#!/bin/sh
set -eu

npx hardhat node --hostname 0.0.0.0 &
hardhat_pid=$!

stop_hardhat() {
  kill "$hardhat_pid" 2>/dev/null || true
  wait "$hardhat_pid" 2>/dev/null || true
}
trap stop_hardhat INT TERM EXIT

ready=false
attempt=0
while [ "$attempt" -lt 60 ]; do
  if node -e "fetch('http://127.0.0.1:8545',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({jsonrpc:'2.0',id:1,method:'eth_chainId',params:[]})}).then(r=>r.json()).then(v=>process.exit(v.result==='0x7a69'?0:1)).catch(()=>process.exit(1))"; then
    ready=true
    break
  fi
  if ! kill -0 "$hardhat_pid" 2>/dev/null; then
    wait "$hardhat_pid"
    exit 1
  fi
  attempt=$((attempt + 1))
  sleep 1
done

if [ "$ready" != true ]; then
  echo "Hardhat JSON-RPC did not become ready on port 8545." >&2
  exit 1
fi

npm run deploy:local
wait "$hardhat_pid"
