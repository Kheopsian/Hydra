#!/bin/bash
# run_one.sh <engine_binary> <torrent> <save_path> <ih> <npieces> <cold|hot> <datafile> <label> [conns]
BIN="$1"; TOR="$2"; SAVE="$3"; IH="$4"; NP="$5"; CM="$6"; DF="$7"; LABEL="$8"; CONNS="${9:-64}"
B=/mnt/cache/appdata/hydra-oss-pub/.sendfile-build
PORT=16400; SOCK=/bench/benchstate/e.sock
docker rm -f bench-seeder >/dev/null 2>&1
for p in $(ss -tlnp 2>/dev/null | grep ':16400' | grep -oE 'pid=[0-9]+' | cut -d= -f2 | sort -u); do kill -9 $p 2>/dev/null; done
sleep 1
rm -rf $B/benchstate/state; mkdir -p $B/benchstate/state/resume; rm -f $B/benchstate/e.sock
cat > $B/benchstate/cfg.json <<CFG
{"data_dir":"/bench/state","resume_dir":"/bench/state/resume","listen_port":$PORT,"listen_addr":"0.0.0.0","max_connections":20000,"max_connections_per_torrent":20000,"max_uploads_per_torrent":10000,"unchoke_slots":-1,"peer_timeout":300,"inactivity_timeout":300,"peer_fingerprint":"-HYBENC-","user_agent":"bench","disable_internal_announce":true,"dht_enabled":false,"pex_enabled":false,"aio_threads":16,"file_pool_size":3000,"cache_size_blocks":32768,"cache_expiry":120,"upload_limit":0,"download_limit":0}
CFG
docker run -d --name bench-seeder --network host -e TYPHON_DISABLE_UTP=1 \
  -v $BIN:/usr/local/bin/hydra-engine:ro -v /mnt/datapool:/datapool -v /mnt/race:/race -v $B:/bench \
  --entrypoint hydra-engine hydra-go:prod --config /bench/benchstate/cfg.json --socket $SOCK >/dev/null
for i in $(seq 1 30); do [ -S $B/benchstate/e.sock ] && break; sleep 1; done
python3 $B/add.py $B/benchstate/e.sock /bench/$(basename $TOR) "$SAVE" >/dev/null 2>&1
sleep 4
sync
if [ "$CM" = "cold" ]; then echo 3 > /proc/sys/vm/drop_caches; echo 3 > /proc/sys/vm/drop_caches
else cat "$DF" > /dev/null 2>&1; cat "$DF" > /dev/null 2>&1; fi
PID=$(docker inspect -f '{{.State.Pid}}' bench-seeder)
read u1 s1 < <(awk '{print $14,$15}' /proc/$PID/stat)
( iostat -x 5 6 > /tmp/bench_iostat.txt 2>/dev/null ) &
( for i in $(seq 1 30); do ps -L -p $PID -o stat= 2>/dev/null | grep -c '^D'; sleep 1; done > /tmp/bench_dthreads.txt ) &
$B/leecher/leecher -addr 127.0.0.1:$PORT -ih $IH -pieces $NP -plen 1048576 -conns $CONNS -dur 30 -pattern random -window 16 > /tmp/bench_leecher.txt 2>&1
read u2 s2 < <(awk '{print $14,$15}' /proc/$PID/stat)
wait
CPU=$(( (u2-u1+s2-s1)/30 ))
DTH=$(awk '{s+=$1;n++} END{if(n)printf "%.1f",s/n}' /tmp/bench_dthreads.txt)
SDC=$(awk '/^sdc /{s+=$NF;n++} END{if(n)printf "%.0f",s/n}' /tmp/bench_iostat.txt)
NVM=$(awk '/^nvme1n1 /{s+=$NF;n++} END{if(n)printf "%.0f",s/n}' /tmp/bench_iostat.txt)
echo "===== [$LABEL] mode=$CM conns=$CONNS ====="
grep TOTAL /tmp/bench_leecher.txt
echo "seeder_engine_CPU%=$CPU  avg_D_threads=$DTH  sdc_util%=$SDC  nvme_util%=$NVM"
docker rm -f bench-seeder >/dev/null 2>&1
