import socket, json, sys, time
# usage: add.py <socketpath> <torrent_path_in_container> <save_path_in_container>
sp, tp, save = sys.argv[1], sys.argv[2], sys.argv[3]
s=socket.socket(socket.AF_UNIX); s.connect(sp)
req=json.dumps({"method":"add_torrent","params":{"torrent_path":tp,"save_path":save,"seed_mode":True,"stopped":False},"id":1})+"\n"
s.sendall(req.encode())
buf=b""
while b"\n" not in buf: buf+=s.recv(65536)
print("ADD_RESP:",buf.decode().strip()[:200])
