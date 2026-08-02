import hashlib, os, sys
# usage: mk_torrent.py <datafile> <out.torrent> <container_save_path>
f, out, csave = sys.argv[1], sys.argv[2], sys.argv[3]
PLEN = 1<<20
size = os.path.getsize(f)
npieces = (size + PLEN - 1)//PLEN
pieces = b"\x00"*20*npieces   # fake (seed_mode skips verify)
name = os.path.basename(f).encode()
def be(x):
    if isinstance(x,int): return b"i"+str(x).encode()+b"e"
    if isinstance(x,bytes): return str(len(x)).encode()+b":"+x
    if isinstance(x,str): return be(x.encode())
    if isinstance(x,list): return b"l"+b"".join(be(i) for i in x)+b"e"
    if isinstance(x,dict): return b"d"+b"".join(be(k)+be(v) for k,v in sorted(x.items()))+b"e"
info={"name":name,"piece length":PLEN,"pieces":pieces,"length":size}
ih=hashlib.sha1(be(info)).hexdigest()
open(out,"wb").write(be({"info":info,"announce":b"http://0.0.0.0:1/x"}))
print("INFO_HASH=%s NPIECES=%d PLEN=%d SIZE=%d SAVE=%s NAME=%s"%(ih,npieces,PLEN,size,csave,name.decode()))
