#!/usr/bin/env python3
"""Capture the pinned official simulate via its own framebuffer screenshot action.

Uses only the process/window it starts. Requires the Linux X11 test baseline and
standard Xlib; does not alter desktop settings or install tools. The caller supplies a
committed fixture XML and optionally a copied camera in that model.
"""
import argparse, ctypes as c, json, os, re, subprocess, time
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--sdk',required=True,type=Path);p.add_argument('--xml',required=True,type=Path)
p.add_argument('--out',required=True,type=Path);p.add_argument('--width',type=int,default=1100);p.add_argument('--height',type=int,default=760);p.add_argument('--camera-index',type=int,default=-1)
a=p.parse_args();assert a.xml.is_file(), a.xml;out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
x=c.CDLL('libX11.so.6')
x.XOpenDisplay.argtypes=[c.c_char_p];x.XOpenDisplay.restype=c.c_void_p
display=x.XOpenDisplay(os.environ.get('DISPLAY',':1').encode())
if not display:raise SystemExit('Cannot connect to X11')
x.XDefaultRootWindow.argtypes=[c.c_void_p];x.XDefaultRootWindow.restype=c.c_ulong
x.XQueryTree.argtypes=[c.c_void_p,c.c_ulong,c.POINTER(c.c_ulong),c.POINTER(c.c_ulong),c.POINTER(c.POINTER(c.c_ulong)),c.POINTER(c.c_uint)]
x.XInternAtom.argtypes=[c.c_void_p,c.c_char_p,c.c_int];x.XInternAtom.restype=c.c_ulong
x.XGetWindowProperty.argtypes=[c.c_void_p,c.c_ulong,c.c_ulong,c.c_long,c.c_long,c.c_int,c.c_ulong,c.POINTER(c.c_ulong),c.POINTER(c.c_int),c.POINTER(c.c_ulong),c.POINTER(c.c_ulong),c.POINTER(c.POINTER(c.c_ubyte))]
x.XFree.argtypes=[c.c_void_p]
x.XMoveResizeWindow.argtypes=[c.c_void_p,c.c_ulong,c.c_int,c.c_int,c.c_uint,c.c_uint]
x.XRaiseWindow.argtypes=[c.c_void_p,c.c_ulong];x.XSetInputFocus.argtypes=[c.c_void_p,c.c_ulong,c.c_int,c.c_ulong]
x.XFlush.argtypes=[c.c_void_p];x.XSync.argtypes=[c.c_void_p,c.c_int]
x.XStringToKeysym.argtypes=[c.c_char_p];x.XStringToKeysym.restype=c.c_ulong
x.XKeysymToKeycode.argtypes=[c.c_void_p,c.c_ulong];x.XKeysymToKeycode.restype=c.c_ubyte
class KeyEvent(c.Structure):
 _fields_=[('type',c.c_int),('serial',c.c_ulong),('send_event',c.c_int),('display',c.c_void_p),('window',c.c_ulong),('root',c.c_ulong),('subwindow',c.c_ulong),('time',c.c_ulong),('x',c.c_int),('y',c.c_int),('x_root',c.c_int),('y_root',c.c_int),('state',c.c_uint),('keycode',c.c_uint),('same_screen',c.c_int)]
class Event(c.Union):
 _fields_=[('key',KeyEvent),('pad',c.c_long*24)]
x.XSendEvent.argtypes=[c.c_void_p,c.c_ulong,c.c_int,c.c_long,c.POINTER(Event)]
root=x.XDefaultRootWindow(display);pid_atom=x.XInternAtom(display,b'_NET_WM_PID',False)
def window_pid(w):
 actual=c.c_ulong();fmt=c.c_int();n=c.c_ulong();remaining=c.c_ulong();data=c.POINTER(c.c_ubyte)()
 r=x.XGetWindowProperty(display,w,pid_atom,0,1,False,0,c.byref(actual),c.byref(fmt),c.byref(n),c.byref(remaining),c.byref(data))
 value=c.cast(data,c.POINTER(c.c_ulong))[0] if not r and n.value and data else None
 if data:x.XFree(data)
 return value
def visible_client(w):
 info=subprocess.run(['xwininfo','-id',hex(w)],capture_output=True,text=True).stdout
 width=re.search(r'Width:\s*(\d+)',info);height=re.search(r'Height:\s*(\d+)',info)
 return 'Map State: IsViewable' in info and width and height and int(width[1])>100 and int(height[1])>100
def windows(w):
 r=c.c_ulong();parent=c.c_ulong();children=c.POINTER(c.c_ulong)();count=c.c_uint()
 if not x.XQueryTree(display,w,c.byref(r),c.byref(parent),c.byref(children),c.byref(count)):return
 ids=[children[i] for i in range(count.value)]
 if children:x.XFree(children)
 for child in ids:
  yield child
  yield from windows(child)
def key(name,ctrl=False,shift=False):
 x.XRaiseWindow(display,wid);x.XSetInputFocus(display,wid,2,0);x.XSync(display,False)
 modifiers=(['Control_L'] if ctrl else [])+(['Shift_L'] if shift else [])
 names=modifiers+[name];state=0
 def send(label,pressed):
  event=Event();event.key=KeyEvent(type=2 if pressed else 3,display=display,window=wid,root=root,state=state,keycode=x.XKeysymToKeycode(display,x.XStringToKeysym(label.encode())),same_screen=True)
  x.XSendEvent(display,wid,False,1 if pressed else 2,c.byref(event));x.XFlush(display)
 for label in names:
  send(label,True)
  if label=='Control_L':state|=4
  if label=='Shift_L':state|=1
 time.sleep(.04)
 for label in reversed(names):
  send(label,False)
  if label=='Control_L':state&=~4
  if label=='Shift_L':state&=~1
 time.sleep(.2)
log=(out/'simulate.log').open('w');proc=subprocess.Popen([str((a.sdk/'bin/simulate').resolve()),str(a.xml.resolve())],cwd=out,stdout=log,stderr=subprocess.STDOUT)
shots=[]
try:
 wid=None;end=time.monotonic()+15
 while time.monotonic()<end and proc.poll() is None:
  wid=next((w for w in windows(root) if window_pid(w)==proc.pid and visible_client(w)),None)
  if wid:break
  time.sleep(.1)
 if not wid:raise RuntimeError('Owned MuJoCo window not found')
 x.XMoveResizeWindow(display,wid,0,0,a.width,a.height);x.XRaiseWindow(display,wid);x.XSync(display,False);time.sleep(.3);x.XSetInputFocus(display,wid,2,0);x.XSync(display,False)
 time.sleep(1.5);key('space');key('BackSpace')
 x.XMoveResizeWindow(display,wid,0,0,a.width,a.height);x.XSync(display,False);time.sleep(.3)
 for _ in range(a.camera_index+1):key('bracketright')
 def shot(name):
  path=out/'screenshot.png'
  if path.exists():path.unlink()
  key('p',ctrl=True)
  end=time.monotonic()+5
  while not path.exists() and time.monotonic()<end:time.sleep(.1)
  if not path.exists():raise RuntimeError('Official screenshot action did not write '+name)
  target=out/(name+'.png');path.replace(target);shots.append(target.name)
 shot('default-both')
 key('Tab');shot('right-only')
 key('Tab',shift=True);shot('neither')
 key('Tab');shot('left-only')
 key('Tab',shift=True)
 for n in range(1,5):key('F'+str(n));shot('f'+str(n));key('F'+str(n))
 key('q',ctrl=True)
 proc.wait(timeout=10)
 (out/'reference.json').write_text(json.dumps({'version':'3.16.0','binary':str((a.sdk/'bin/simulate').resolve()),'model':str(a.xml.resolve()),'requested_width':a.width,'requested_height':a.height,'camera_index':a.camera_index,'shots':shots,'method':'Official GLFW window, X11 keyboard events to the owned client, original Ctrl+P framebuffer screenshot'},indent=2)+'\n')
 print('Captured',len(shots),'official reference frames in',out)
finally:
 if proc.poll() is None:proc.terminate();proc.wait(timeout=10)
 log.close()
