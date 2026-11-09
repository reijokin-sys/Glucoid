#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Finite synthetic HTTPS contract/security suite. No real settings or data."""
import http.server,ssl,socket,subprocess,os,json,time,threading,tempfile,re,gzip,hashlib,argparse
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
A='LAB_READER_A';B='LAB_READER_B';SECRET='LAB_API_SECRET';JA='LAB_JWT_A';JB='LAB_JWT_B'
class Server(http.server.ThreadingHTTPServer):
 daemon_threads=True
 def handle_error(self,*_):pass
 def __init__(self,mode,context):
  super().__init__(('127.0.0.1',0),Handler);self.mode=mode;self.events=[];self.redirect='';self.socket=context.wrap_socket(self.socket,server_side=True)
  self.thread=threading.Thread(target=lambda:self.serve_forever(poll_interval=.02),daemon=True);self.thread.start()
 @property
 def url(self):return 'https://localhost:'+str(self.server_port)+'/prefix'
class Handler(http.server.BaseHTTPRequestHandler):
 def log_message(self,*_):pass
 def do_GET(self):
  from urllib.parse import urlsplit,parse_qs,unquote
  u=urlsplit(self.path);q=parse_qs(u.query);p=u.path;bearer=self.headers.get('Authorization','');secret=self.headers.get('api-secret','');mode=self.server.mode
  kind='jwt' if '/authorization/request/' in p else ('v3' if '/v3/' in p else ('v2' if '/v2/' in p else 'v1'))
  event={'kind':kind,'token_query':bool(q.get('token')),'bearer_a':bearer=='Bearer '+JA,'bearer_b':bearer=='Bearer '+JB,'secret_header_correct':secret==hashlib.sha1(SECRET.encode()).hexdigest(),'has_any_auth':bool(bearer or secret or q.get('token')),'reader_a_in_jwt_path':kind=='jwt' and unquote(p.split('/')[-1])==A}
  self.server.events.append(event)
  status=200;body=None;encoding=None
  if kind=='jwt':
   if mode=='slow':time.sleep(12)
   if mode=='delayed':time.sleep(.3)
   given=unquote(p.split('/')[-1]);expected=B if mode=='reader-b' else A
   if mode=='v1':status=404
   elif given!=expected:status=401
   else:body={'token':JB if mode=='reader-b' else JA}
  else:
   if mode=='v2' and kind=='v3':status=404
   elif mode=='v1' and kind!='v1':status=404
   elif mode=='secret' and not event['secret_header_correct']:status=403
   elif mode=='none' and event['has_any_auth']:status=403
   elif mode not in ['secret','none','v1'] and bearer!='Bearer '+(JB if mode=='reader-b' else JA):status=403
   elif mode=='v1' and q.get('token')!=[A]:status=403
   rows=[{'sgv':108,'date':int(time.time()*1000),'direction':'Flat'},{'sgv':90,'date':int(time.time()*1000)-300000,'direction':'Flat'}]
   body={'status':200,'result':rows} if kind=='v3' else rows
   if mode=='malformed':body={'result':'not-an-array'}
   if mode=='invalid-rows':body={'status':200,'result':[None]}
   if mode=='redirect':status=302
  data=json.dumps(body if body is not None else {'status':status}).encode()
  if mode=='oversized' and kind!='jwt':data=b'x'*(1024*1024+1)
  if mode=='gzip-large' and kind!='jwt':data=gzip.compress(b'x'*(1024*1024+1));encoding='gzip'
  try:
   self.send_response(status)
   if status==302:self.send_header('Location',self.server.redirect)
   self.send_header('Content-Type','application/json')
   if mode=='headers-large' and kind!='jwt':self.send_header('X-Lab','x'*17000)
   if mode=='chunked' and kind!='jwt':self.send_header('Transfer-Encoding','chunked')
   else:self.send_header('Content-Length',str(len(data)))
   if encoding:self.send_header('Content-Encoding',encoding)
   self.end_headers()
   if mode=='chunked' and kind!='jwt':self.wfile.write(('%x\r\n'%len(data)).encode()+data+b'\r\n0\r\n\r\n')
   else:self.wfile.write(data)
  except (BrokenPipeError,ConnectionResetError,ssl.SSLError):pass

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,required=True);parser.add_argument('--probe',type=Path,required=True);parser.add_argument('--case',action='append');args=parser.parse_args();args.output.mkdir(parents=True,exist_ok=True)
 # No private key file: OpenSSL output is captured only in memory, then loaded through memfd.
 pem=subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-days','1','-keyout','/dev/stdout','-out','/dev/stdout','-subj','/CN=synthetic-lab','-addext','subjectAltName=DNS:localhost,IP:127.0.0.1'],capture_output=True,check=True,timeout=15).stdout
 public=re.search(b'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----',pem,re.S)[0]
 cert=args.output/'public-test-ca.pem';cert.write_bytes(public+b'\n');os.chmod(cert,0o644)
 fd=os.memfd_create('synthetic-tls-key',os.MFD_CLOEXEC);os.write(fd,pem);context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);context.load_cert_chain('/proc/self/fd/'+str(fd));os.close(fd);pem=None
 owner=args.output.stat();prefix=['setpriv','--reuid',str(owner.st_uid),'--regid',str(owner.st_gid),'--clear-groups','--no-new-privs'] if os.geteuid()==0 else []
 results=[];servers=[]
 def server(mode):
  s=Server(mode,context);servers.append(s);return s
 def run(name,s,extra=(),expect=True,trust=True):
  if args.case and name not in args.case:return {'pass':True,'result':{},'skipped':True}
  args2=prefix+[str(args.probe),'--source','nightscout','--address',s.url,'--auth','token','--credential',A]
  if trust:args2+=['--ca',str(cert)]
  args2+=list(extra);p=subprocess.run(args2,capture_output=True,text=True,timeout=16,cwd=ROOT)
  (args.output/(name+'-stderr.txt')).write_text(p.stderr)
  try:r=json.loads(p.stdout)
  except ValueError:r={'ok':False,'harness_error':True}
  row={'case':name,'pass':r.get('ok')==expect and not r.get('harness_error'),'result':r,'events':s.events.copy()};results.append(row);print(json.dumps({'case':name,'pass':row['pass']}),flush=True);return row
 try:
  run('https-token-v3-no-vpn',server('v3'))
  run('https-token-v2-fallback',server('v2'))
  run('https-token-v1-legacy',server('v1'))
  run('api-secret-header',server('secret'),['--auth','apisecret','--credential',SECRET])
  run('no-auth-with-unused-credential',server('none'),['--auth','none'])
  run('wrong-credential',server('v3'),['--credential','LAB_INVALID'],expect=False)
  missing=server('v3');r=run('missing-credential',missing,['--credential',''],expect=False);r['pass'] &= not missing.events
  scope=server('v3');r=run('wrong-credential-scope',scope,['--wrong-scope'],expect=False);r['pass'] &= not scope.events
  run('untrusted-certificate',server('v3'),expect=False,trust=False)
  run('malformed-json',server('malformed'),expect=False)
  run('invalid-entry-row',server('invalid-rows'),expect=False)
  run('chunked-response',server('chunked'))
  sink=server('none');redirect=server('redirect');redirect.redirect=sink.url+'/api/v1/entries.json';r=run('redirect-blocked',redirect,expect=False);r['pass'] &= not sink.events
  run('oversized-response',server('oversized'),expect=False)
  run('decompressed-response-limit',server('gzip-large'),expect=False)
  run('header-limit',server('headers-large'),expect=False)
  first=server('v3');second=server('none');r=run('prior-jwt-new-no-auth-server',first,['--switch-on-success','--switch-address',second.url,'--switch-auth','none']);r['second_events']=second.events.copy();r['pass'] &= bool(second.events) and all(not e['has_any_auth'] for e in second.events)
  first=server('v3');second=server('reader-b');r=run('old-credential-scope-cannot-cross',first,['--switch-on-success','--switch-address',second.url,'--keep-old-scope-on-switch'],expect=False);r['pass'] &= not second.events
  first=server('delayed');second=server('reader-b');r=run('overlapping-settings-change',first,['--switch-after-ms','50','--switch-address',second.url,'--switch-credential',B]);r['second_events']=second.events.copy();r['pass'] &= r['result'].get('success_events')==1 and r['result'].get('failure_events')==0 and all(not e['bearer_a'] and not e['reader_a_in_jwt_path'] for e in second.events)
  r=run('explicit-cancel',server('delayed'),['--cancel-after-ms','50'],expect=False);r['pass'] &= r['result'].get('success_events')==0 and r['result'].get('failure_events')==0 and r['result'].get('elapsed_ms',99999)<1000
  r=run('real-ten-second-deadline',server('slow'),expect=False);r['pass'] &= 9500<=r['result'].get('elapsed_ms',0)<=11500
 finally:
  for s in servers:s.shutdown();s.server_close()
  report={'results':results,'passed':sum(r['pass'] for r in results),'total':len(results),'real_data_used':False}
  path=args.output/'results.json';path.write_text(json.dumps(report,indent=2)+'\n')
  if os.geteuid()==0:
   for p in args.output.iterdir():
    if p.is_file():os.chown(p,owner.st_uid,owner.st_gid);os.chmod(p,0o640)
 return 0 if all(r['pass'] for r in results) else 1
if __name__=='__main__':raise SystemExit(main())
