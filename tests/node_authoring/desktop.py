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
X.XGetTransientForHint.argtypes=[P,U,c.POINTER(U)]
X.XGetGeometry.argtypes=[P,U,c.POINTER(U),c.POINTER(I),c.POINTER(I),c.POINTER(c.c_uint),c.POINTER(c.c_uint),c.POINTER(c.c_uint),c.POINTER(c.c_uint)]
X.XTranslateCoordinates.argtypes=[P,U,U,I,I,c.POINTER(I),c.POINTER(I),c.POINTER(U)]
class WindowAttributes(c.Structure):
    _fields_=[('x',I),('y',I),('width',I),('height',I),('border_width',I),('depth',I),('visual',P),('root',U),('window_class',I),('bit_gravity',I),('win_gravity',I),('backing_store',I),('backing_planes',U),('backing_pixel',U),('save_under',I),('colormap',U),('map_installed',I),('map_state',I),('all_event_masks',c.c_long),('your_event_mask',c.c_long),('do_not_propagate_mask',c.c_long),('override_redirect',I),('screen',P)]
X.XGetWindowAttributes.argtypes=[P,U,c.POINTER(WindowAttributes)]
class CrossingEvent(c.Structure):
    _fields_=[('type',I),('serial',U),('send_event',I),('display',P),('window',U),('root',U),('subwindow',U),('time',U),('x',I),('y',I),('x_root',I),('y_root',I),('mode',I),('detail',I),('same_screen',I),('focus',I),('state',c.c_uint)]
class MouseEvent(c.Structure):
    _fields_=CrossingEvent._fields_[:12]+[('state',c.c_uint),('button',c.c_uint),('same_screen',I)]
class XEvent(c.Union):
    _fields_=[('crossing',CrossingEvent),('mouse',MouseEvent),('pad',c.c_long*24)]
X.XSendEvent.argtypes=[P,U,I,c.c_long,c.POINTER(XEvent)]
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
                X.XRaiseWindow(self.d,w);X.XSetInputFocus(self.d,w,2,0);X.XSync(self.d,0);time.sleep(.25);return w
        raise RuntimeError('Test editor window not found')
    def move(self,x,y):T.XTestFakeMotionEvent(self.d,-1,int(x),int(y),0);X.XSync(self.d,0)
    def enter(self,rect):
        """Notify the owned native window when Xwayland's input overlay hides entry.

        Godot's public Input API sends motion/button events, but native dialogs
        also require the window enter notification used by release-mode Buttons.
        """
        def owned(window,seen=None):
            seen=set() if seen is None else seen
            if window in seen:return False
            seen.add(window)
            if self.window_pid(window)==self.pid:return True
            parent=U()
            return bool(X.XGetTransientForHint(self.d,window,c.byref(parent))) and owned(parent.value,seen)
        gx=int(rect[0]+min(100,rect[2]/2));gy=int(rect[1]+rect[3]/2)
        candidates=[];stack=self.children(self.root)
        while stack:
            window=stack.pop();stack.extend(self.children(window))
            if not owned(window):continue
            attributes=WindowAttributes()
            if not X.XGetWindowAttributes(self.d,window,c.byref(attributes)) or attributes.map_state!=2:continue
            root=U();x=I();y=I();width=c.c_uint();height=c.c_uint();border=c.c_uint();depth=c.c_uint();child=U()
            X.XGetGeometry(self.d,window,c.byref(root),c.byref(x),c.byref(y),c.byref(width),c.byref(height),c.byref(border),c.byref(depth))
            X.XTranslateCoordinates(self.d,window,self.root,0,0,c.byref(x),c.byref(y),c.byref(child))
            if x.value<=gx<x.value+width.value and y.value<=gy<y.value+height.value:
                candidates.append((width.value*height.value,window,x.value,y.value))
        if not candidates:raise RuntimeError('No owned Godot window at click point')
        _,window,x,y=min(candidates)
        event=XEvent();event.crossing=CrossingEvent(7,0,1,self.d,window,self.root,0,0,gx-x,gy-y,gx,gy,0,0,1,1,0)
        X.XSendEvent(self.d,window,0,1<<4,c.byref(event));X.XSync(self.d,0)
        return window,gx-x,gy-y,gx,gy
    def window_click(self,rect,count=1,target_rect=None):
        window,x,y,gx,gy=self.enter(target_rect or rect)
        if target_rect is not None:
            origin_x=gx-x;origin_y=gy-y
            gx=int(rect[0]+min(100,rect[2]/2));gy=int(rect[1]+rect[3]/2)
            x=gx-origin_x;y=gy-origin_y
        events=[(6,1<<6,0)]+[(kind,mask,state) for _ in range(count) for kind,mask,state in [(4,1<<2,0),(5,1<<3,1<<8)]]
        for kind,mask,state in events:
            if kind==5 and target_rect is not None:
                # A popup closes on the outside press. The release belongs to
                # the now-uncovered parent window, as with the native grab.
                window,x,y,gx,gy=self.enter(rect)
            event=XEvent();event.mouse=MouseEvent(kind,0,1,self.d,window,self.root,0,0,x,y,gx,gy,state,1,1)
            X.XSendEvent(self.d,window,0,mask,c.byref(event));X.XSync(self.d,0);time.sleep(.1)
    def window_motion(self,x,y):
        window,local_x,local_y,gx,gy=self.enter([x,y,0,0])
        event=XEvent();event.mouse=MouseEvent(6,0,1,self.d,window,self.root,0,0,local_x,local_y,gx,gy,0,0,1)
        X.XSendEvent(self.d,window,0,1<<6,c.byref(event));X.XSync(self.d,0)
    def window_key(self,name,ctrl=False,shift=False):
        window=self.focus()
        code=X.XKeysymToKeycode(self.d,X.XStringToKeysym(name.encode()))
        state=(4 if ctrl else 0)|(1 if shift else 0)
        for kind,mask in [(2,1),(3,2)]:
            event=XEvent();event.mouse=MouseEvent(kind,0,1,self.d,window,self.root,0,0,0,0,0,0,state,code,1)
            X.XSendEvent(self.d,window,0,mask,c.byref(event));X.XSync(self.d,0);time.sleep(.08)
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
