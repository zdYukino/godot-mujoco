"""Tiny X11/XTEST adapter; only operates the explicitly supplied Godot test PID."""
import ctypes as c
import time
from PIL import ImageGrab
X=c.CDLL('libX11.so.6'); T=c.CDLL('libXtst.so.6')
P=c.c_void_p; U=c.c_ulong; I=c.c_int
for name,args,rest in [('XOpenDisplay',[c.c_char_p],P),('XDefaultRootWindow',[P],U),('XInternAtom',[P,c.c_char_p,I],U),('XStringToKeysym',[c.c_char_p],U),('XKeysymToKeycode',[P,U],c.c_ubyte),('XQueryTree',[P,U,c.POINTER(U),c.POINTER(U),c.POINTER(c.POINTER(U)),c.POINTER(c.c_uint)],I),('XGetWindowProperty',[P,U,U,c.c_long,c.c_long,I,U,c.POINTER(U),c.POINTER(I),c.POINTER(U),c.POINTER(U),c.POINTER(c.POINTER(c.c_ubyte))],I),('XSetInputFocus',[P,U,I,U],I),('XRaiseWindow',[P,U],I),('XSync',[P,I],I),('XFree',[P],I)]:
    f=getattr(X,name);f.argtypes=args;f.restype=rest
T.XTestFakeMotionEvent.argtypes=[P,I,I,I,U]
T.XTestFakeButtonEvent.argtypes=[P,c.c_uint,I,U]
T.XTestFakeKeyEvent.argtypes=[P,c.c_uint,I,U]
class Desktop:
    def __init__(self,pid,display=':0'):
        self.pid=pid;self.display=display;self.d=X.XOpenDisplay(display.encode())
        if not self.d:raise RuntimeError('No X11 display')
        self.root=X.XDefaultRootWindow(self.d)
    def children(self,w):
        root,parent=U(),U();children=c.POINTER(U)();count=c.c_uint()
        X.XQueryTree(self.d,w,c.byref(root),c.byref(parent),c.byref(children),c.byref(count))
        result=[children[i] for i in range(count.value)]
        if children:X.XFree(children)
        return result
    def window_pid(self,w):
        actual,format,count,remaining=U(),I(),U(),U();data=c.POINTER(c.c_ubyte)()
        atom=X.XInternAtom(self.d,b'_NET_WM_PID',0)
        X.XGetWindowProperty(self.d,w,atom,0,1,0,6,c.byref(actual),c.byref(format),c.byref(count),c.byref(remaining),c.byref(data))
        result=c.cast(data,c.POINTER(U))[0] if data and count.value else 0
        if data:X.XFree(data)
        return result
    def focus(self):
        stack=self.children(self.root)
        while stack:
            w=stack.pop()
            stack.extend(self.children(w))
            if self.window_pid(w)==self.pid:
                X.XRaiseWindow(self.d,w);X.XSetInputFocus(self.d,w,2,0);X.XSync(self.d,0);time.sleep(.25);return
        raise RuntimeError('Test editor window not found')
    def move(self,x,y):T.XTestFakeMotionEvent(self.d,-1,int(x),int(y),0);X.XSync(self.d,0)
    def button(self,down):T.XTestFakeButtonEvent(self.d,1,int(down),0);X.XSync(self.d,0)
    def click(self,rect,count=1):
        x,y,w,h=rect;self.move(x+min(w/2,100),y+h/2)
        for _ in range(count):self.button(True);time.sleep(.06);self.button(False);time.sleep(.07)
        time.sleep(.3)
    def key(self,name,ctrl=False,shift=False):
        mods=(['Control_L'] if ctrl else [])+(['Shift_L'] if shift else [])
        def event(key,down):T.XTestFakeKeyEvent(self.d,X.XKeysymToKeycode(self.d,X.XStringToKeysym(key.encode())),int(down),0)
        for m in mods:event(m,True)
        event(name,True);event(name,False)
        for m in reversed(mods):event(m,False)
        X.XSync(self.d,0);time.sleep(.08)
    def type(self,value):
        self.key('a',ctrl=True)
        mapping={'/':'slash','.':'period','-':'minus','_':'underscore',':':'colon',' ':'space'}
        for ch in value:self.key(mapping.get(ch,ch))
    def drag(self,start,end):
        self.move(*start);self.button(True);time.sleep(.2)
        for i in range(1,21):self.move(start[0]+(end[0]-start[0])*i/20,start[1]+(end[1]-start[1])*i/20);time.sleep(.03)
        self.button(False);time.sleep(.5)
    def shot(self,path):ImageGrab.grab(xdisplay=self.display).save(path)
