#!/bin/bash
B=/mnt/cache/appdata/hydra-oss-pub/.sendfile-build
R=/tmp/campaign_results.txt
exec > $R 2>&1
echo "=== CAMPAIGN START $(date) ==="
echo "--- stopping prod hydra-go to free CPU+disk ---"
docker stop -t 60 hydra-go
echo "prod stopped: $(docker inspect -f '{{.State.Status}}' hydra-go)"
ZT=$B/zfs.torrent; ZS='/datapool/data/downloads/movies/Troy.2004.Director.s.Cut.MULTi.VF2.2160p.4K.BluRay.HDR.x265.TrueHD.5.1.AC3.5.1-TireXo'; ZIH=9a36348daeb79ad117775d36ff14456e75b16b00; ZNP=93592
HT=$B/hot.torrent; HS=/race; HIH=$(python3 $B/mk_torrent.py /mnt/race/benchhot.bin /tmp/x.torrent /race | grep -oE 'INFO_HASH=[a-f0-9]+' | cut -d= -f2); HNP=6144; HF=/mnt/race/benchhot.bin
echo "hot ih=$HIH"
echo; echo "########## COLD-ZFS (spinning, random, 128 conns) ##########"
for v in old sendfile hybrid; do
  BIN=$B/bin/engine-$v; [ "$v" = hybrid ] && BIN=$B/hybrid/typhon-engine/target/release/typhon-engine
  bash $B/run_one.sh $BIN $ZT "$ZS" $ZIH $ZNP cold /dev/null "COLD-$v" 128
done
echo; echo "########## HOT-CACHED (resident, random, 64 conns) ##########"
for v in old sendfile hybrid; do
  BIN=$B/bin/engine-$v; [ "$v" = hybrid ] && BIN=$B/hybrid/typhon-engine/target/release/typhon-engine
  bash $B/run_one.sh $BIN $HT "$HS" $HIH $HNP hot $HF "HOT-$v" 64
done
echo; echo "--- restarting prod (sendfile image, host mode full-direct) ---"
docker rm -f bench-seeder >/dev/null 2>&1
docker run -d --name hydra-go --restart unless-stopped --privileged --network host \
  --ulimit nofile=1000000:1000000 \
  -v /mnt/cache/appdata/hydra:/configs -v /mnt/datapool/data:/data \
  -v /mnt/race:/race -v /mnt/calepool/data:/calewood \
  -e GIN_MODE=release -e TZ=Europe/Paris -e TYPHON_DISABLE_UTP=1 -e GOMEMLIMIT=8GiB \
  -e HYDRA_CONFIG_DIR=/configs -e TYPHON_SELF_IPS=86.196.105.98 \
  -e MALLOC_CONF=prof:true,prof_active:true,lg_prof_sample:19,prof_prefix:/configs/jeprof \
  hydra-go:sendfile >/dev/null
sleep 3; prlimit --pid $(docker inspect -f '{{.State.Pid}}' hydra-go) --nofile=1000000:1000000
echo "prod restarted: $(docker inspect -f '{{.State.Status}}' hydra-go)"
echo "=== CAMPAIGN DONE $(date) ==="
