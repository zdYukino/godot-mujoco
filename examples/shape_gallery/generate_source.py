"""Original small convex cone + native primitive MJCF, no third-party geometry."""
from pathlib import Path
from math import cos, sin, tau
n=32
vertices=[(.38*cos(i*tau/n),.38*sin(i*tau/n),-.45) for i in range(n)]+[(0,0,.45)]
faces=[(i,(i+1)%n,n) for i in range(n)]+[(0,i+1,i) for i in range(1,n-1)]
def nums(rows): return ' '.join(' '.join(format(v,'.9g') for v in row) for row in rows)
shapes=[('sphere','sphere','.35','-2.5 0 2','0.9 0.25 0.18 1'),('box','box','.35 .35 .35','-1.2 0 2.6','0.2 0.55 0.95 1'),('cylinder','cylinder','.32 .45','0 0 3.2','0.25 0.8 0.4 1'),('cone','mesh','','1.3 0 3.8','0.95 0.6 0.12 1'),('capsule','capsule','.24 .25','2.6 0 4.4','0.65 0.3 0.9 1'),('ellipsoid','ellipsoid','.4 .28 .22','3.8 0 3','0.15 0.8 0.8 1'),('probe','sphere','.22','-1.2 0 4.8','1 0.8 0.65 1')]
body=[]
for name,kind,size,pos,color in shapes:
 attrs='mesh="cone_mesh"' if kind=='mesh' else f'size="{size}"'
 body.append(f'<body name="{name}" pos="{pos}"><freejoint name="{name}_free"/><geom name="{name}_geom" type="{kind}" {attrs} mass="{.25 if name=="probe" else 1}" rgba="{color}"/></body>')
xml=f'''<mujoco model="DynamicShapeGallery">
  <compiler angle="radian"/>
  <option timestep="0.002" gravity="0 0 -9.81" integrator="implicitfast" solver="Newton"><flag nativeccd="enable"/></option>
  <default><geom friction="0.9 0.005 0.0001" condim="3" solref="0.02 1"/></default>
  <asset><mesh name="cone_mesh" vertex="{nums(vertices)}" face="{nums(faces)}"/></asset>
  <worldbody>
    <geom name="floor_geom" type="box" size="6 4 .1" pos="0 0 -.1" rgba=".25 .28 .32 1"/>
    {''.join(body)}
  </worldbody>
</mujoco>'''
Path(__file__).with_name('assets').joinpath('gallery.xml').write_text(xml+'\n')
