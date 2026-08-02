package main

import (
	crand "crypto/rand"
	"encoding/binary"
	"encoding/hex"
	"flag"
	"fmt"
	"io"
	mr "math/rand"
	"net"
	"sync"
	"sync/atomic"
	"time"
)

var totalBytes int64
var seqCtr int64

func conn(addr string, ih [20]byte, blocks int64, plen int64, pattern string, window int, stop <-chan struct{}) {
	c, err := net.Dial("tcp", addr)
	if err != nil {
		return
	}
	defer c.Close()
	c.(*net.TCPConn).SetNoDelay(true)
	hs := make([]byte, 68)
	hs[0] = 19
	copy(hs[1:], "BitTorrent protocol")
	copy(hs[28:], ih[:])
	pid := make([]byte, 20)
	crand.Read(pid)
	copy(hs[48:], pid)
	if _, err := c.Write(hs); err != nil {
		return
	}
	if _, err := io.ReadFull(c, make([]byte, 68)); err != nil {
		return
	}
	c.Write([]byte{0, 0, 0, 1, 2}) // interested

	blk := int64(16384)
	perPiece := plen / blk
	sendReq := func() {
		var bi int64
		if pattern == "seq" {
			bi = atomic.AddInt64(&seqCtr, 1) % blocks
		} else {
			bi = mr.Int63n(blocks)
		}
		piece := bi / perPiece
		begin := (bi % perPiece) * blk
		buf := make([]byte, 17)
		binary.BigEndian.PutUint32(buf[0:], 13)
		buf[4] = 6
		binary.BigEndian.PutUint32(buf[5:], uint32(piece))
		binary.BigEndian.PutUint32(buf[9:], uint32(begin))
		binary.BigEndian.PutUint32(buf[13:], uint32(blk))
		c.Write(buf)
	}
	for i := 0; i < window; i++ {
		sendReq()
	}
	hdr := make([]byte, 4)
	for {
		select {
		case <-stop:
			return
		default:
		}
		if _, err := io.ReadFull(c, hdr); err != nil {
			return
		}
		mlen := binary.BigEndian.Uint32(hdr)
		if mlen == 0 {
			continue
		}
		id := make([]byte, 1)
		if _, err := io.ReadFull(c, id); err != nil {
			return
		}
		rest := int(mlen) - 1
		if id[0] == 7 {
			body := make([]byte, rest)
			if _, err := io.ReadFull(c, body); err != nil {
				return
			}
			atomic.AddInt64(&totalBytes, int64(rest-8))
			sendReq()
		} else if rest > 0 {
			io.CopyN(io.Discard, c, int64(rest))
		}
	}
}

func main() {
	addr := flag.String("addr", "127.0.0.1:16400", "seeder addr")
	ihHex := flag.String("ih", "", "info hash hex")
	pieces := flag.Int64("pieces", 0, "num pieces")
	plen := flag.Int64("plen", 1048576, "piece length")
	conns := flag.Int("conns", 32, "concurrent connections")
	dur := flag.Int("dur", 30, "duration s")
	pattern := flag.String("pattern", "random", "random|seq")
	window := flag.Int("window", 16, "outstanding requests per conn")
	flag.Parse()
	ihb, _ := hex.DecodeString(*ihHex)
	var ih [20]byte
	copy(ih[:], ihb)
	blocks := (*pieces * *plen) / 16384
	mr.Seed(time.Now().UnixNano())
	stop := make(chan struct{})
	var wg sync.WaitGroup
	for i := 0; i < *conns; i++ {
		wg.Add(1)
		go func() { defer wg.Done(); conn(*addr, ih, blocks, *plen, *pattern, *window, stop) }()
	}
	last := int64(0)
	for s := 0; s < *dur; s++ {
		time.Sleep(time.Second)
		cur := atomic.LoadInt64(&totalBytes)
		fmt.Printf("  t=%ds  %.2f Gbps\n", s+1, float64(cur-last)*8/1e9)
		last = cur
	}
	close(stop)
	tot := atomic.LoadInt64(&totalBytes)
	fmt.Printf("TOTAL %.1f GB = avg %.2f Gbps over %ds\n", float64(tot)/1e9, float64(tot)*8/float64(*dur)/1e9, *dur)
}
