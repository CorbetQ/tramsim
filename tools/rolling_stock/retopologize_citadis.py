"""Offline clean stylised reconstruction, using Meshy contour study + photo plans.

No paid API. No photographic texture is exported. New static shell AND mechanical
mesh parts are authored as one set; only Godot's animation transforms are reused.
Coordinates below are Godot metres (X lateral, Y up, -Z forward).
blender -b --python tools/rolling_stock/retopologize_citadis.py
"""
import json
import math
from pathlib import Path
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT/'data/rolling_stock/meshy_citadis'
PROFILES = {'angers302':('citadis_302',32.4), 'angers305':('citadis_x05',33.0), 'nantes405':('citadis_x05_nantes',45.6)}
MATERIALS = []
MAT = {}
VERTEX_MAT = None

def material(name, color, metallic=0, roughness=.55, emission=0):
    m=bpy.data.materials.new(name);m.use_nodes=True;m.diffuse_color=(*color,1)
    p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Metallic'].default_value=metallic;p.inputs['Roughness'].default_value=roughness
    if emission:
        p.inputs['Emission Color'].default_value=(*color,1);p.inputs['Emission Strength'].default_value=emission
    MAT[name]=len(MATERIALS);MATERIALS.append(m)


def palette():
    global VERTEX_MAT
    MATERIALS.clear();MAT.clear()
    for n,c in [('porcelain',(.76,.79,.78)),('roof',(.47,.53,.55)),('frame',(.065,.09,.10)),('skirt',(.12,.16,.17)),('bellows',(.055,.075,.08)),('teal',(.045,.15,.145)),('purple',(.28,.09,.43)),('blue',(.05,.35,.64)),('green',(.25,.57,.12)),('yellow',(.86,.69,.07)),('orange',(.86,.36,.055)),('red',(.68,.075,.055))]:material(n,c)
    material('glass',(.025,.05,.07),.35,.16)
    material('glass_reflection',(.07,.15,.20),.25,.20)
    material('steel',(.35,.41,.44),.75,.35)
    material('insulator',(.32,.15,.085),.1)
    material('headlamp',(.89,.91,.78),0,.18,.45)
    material('tail_lamp',(.60,.02,.025),0,.25,.25)
    material('led',(.17,.65,.4),0,.3,.35)
    VERTEX_MAT=bpy.data.materials.new('CitadisPalette');VERTEX_MAT.use_nodes=True
    p=VERTEX_MAT.node_tree.nodes.get('Principled BSDF')
    vc=VERTEX_MAT.node_tree.nodes.new('ShaderNodeVertexColor');vc.layer_name='TramPalette'
    VERTEX_MAT.node_tree.links.new(vc.outputs['Color'],p.inputs['Base Color'])
    p.inputs['Roughness'].default_value=.55



class Mesh:
    def __init__(self,name):self.name=name;self.v=[];self.f=[];self.material=[]
    def face(self,vertices,mat,normal=None):
        vertices=[Vector(v) for v in vertices]
        if normal is not None and (vertices[1]-vertices[0]).cross(vertices[2]-vertices[0]).dot(Vector(normal))<0:vertices.reverse()
        a=len(self.v);self.v.extend(tuple(v) for v in vertices);self.f.append(tuple(range(a,a+len(vertices))));self.material.append(MAT[mat])
    def box(self,c,size,mat):
        x,y,z=c;w,h,l=[n*.5 for n in size]
        v=[(x+sx*w,y+sy*h,z+sz*l) for sx,sy,sz in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
        for ids,n in [([0,3,2,1],(0,0,-1)),([4,5,6,7],(0,0,1)),([0,4,7,3],(-1,0,0)),([1,2,6,5],(1,0,0)),([0,1,5,4],(0,-1,0)),([3,7,6,2],(0,1,0))]:self.face([v[i] for i in ids],mat,n)
    def tube(self,a,b,r,mat,sides=10):
        a=Vector(a);b=Vector(b);axis=(b-a).normalized();q=Vector((1,0,0)) if abs(axis.x)<.85 else Vector((0,1,0));u=axis.cross(q).normalized();v=axis.cross(u).normalized()
        rings=[]
        for p in [a,b]:rings.append([p+r*(math.cos(math.tau*i/sides)*u+math.sin(math.tau*i/sides)*v) for i in range(sides)])
        self.face(rings[0],mat,-axis);self.face(rings[1],mat,axis)
        for i in range(sides):
            j=(i+1)%sides;self.face([rings[0][i],rings[0][j],rings[1][j],rings[1][i]],mat,(rings[0][i]+rings[0][j])*.5-a)
    def object(self):
        # A right-handed rotation from Godot to Blender; scale is already metres.
        mesh=bpy.data.meshes.new(self.name);mesh.from_pydata([(x,-z,y) for x,y,z in self.v],[],self.f);mesh.update()
        mesh.materials.append(VERTEX_MAT)
        colors=mesh.color_attributes.new(name='TramPalette',type='FLOAT_COLOR',domain='CORNER')
        tags=mesh.uv_layers.new(name='MaterialTags')
        for face,index in zip(mesh.polygons,self.material):
            mat=MATERIALS[index];tag=.5 if mat.name.startswith('glass') else (.85 if mat.name=='steel' else 1.)
            if mat.name in ['headlamp','tail_lamp','led']:tag=.1
            for loop in face.loop_indices:
                colors.data[loop].color=mat.diffuse_color
                tags.data[loop].uv=(tag,0)
            face.material_index=0;face.use_smooth=False
        obj=bpy.data.objects.new(self.name,mesh);bpy.context.collection.objects.link(obj);return obj


def lerp_curve(curve,x):
    for (a,av),(b,bv) in zip(curve,curve[1:]):
        if x<=b:return av+(bv-av)*max(0,(x-a)/(b-a))
    return curve[-1][1]


def mesh_y_contour(key):
    """Quantitative shape reference only. We do not resell a photo projection as DA."""
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    path=ROOT/'meshy_output'/(key+'_exterior_texture')/'model.glb'
    if not path.exists():
        recorded=OUT/'contour_study.json'
        if recorded.exists():return json.loads(recorded.read_text())[key]
        raise FileNotFoundError('Download the recorded Meshy task, or retain contour_study.json')
    bpy.ops.import_scene.gltf(filepath=str(path))
    vs=[o.matrix_world@v.co for o in bpy.context.scene.objects if o.type=='MESH' for v in o.data.vertices]
    lo=[min(v[i] for v in vs) for i in range(3)];hi=[max(v[i] for v in vs) for i in range(3)]
    half=(hi[1]-lo[1])*.5;middle=(hi[1]+lo[1])*.5
    result=[]
    for j in range(11):
        h=j/10;z=lo[2]+h*(hi[2]-lo[2])
        points=sorted(abs(v.y-middle)/half for v in vs if v.x<lo[0]+(hi[0]-lo[0])*.10 and abs(v.z-z)<(hi[2]-lo[2])*.065)
        result.append([h,round(max(.65,min(1,points[int((len(points)-1)*.9)] if points else 1)),4)])
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    return result


def paint(key,y,z):
    if key=='nantes405':return 'teal' if .57<y<2.74 else ('skirt' if y<.57 else 'porcelain')
    if y<.48:return 'skirt'
    # Geometric six-colour ribbon, not a sampled photograph. At lower body and
    # shoulder only; glass panes are independent materials.
    phase=(z+.28*(y-1.0))%8.15
    if 1.35<phase<2.85:return ['purple','blue','green','yellow','orange','red'][min(5,int((phase-1.35)/.25))]
    return 'porcelain'


def side_panel(mesh,key,side,a,b,y0,y1,global_centre,override=None,x=1.20):
    # Split the actual face into clipped diagonal paint regions. No painted
    # overlay, pixel texture, stair-stepped strips, or geometry intersection.
    if b-a<.0001:return
    def q(point):
        y,z=point;return z+global_centre+.28*(y-1.0)
    def clip(poly,limit,greater):
        result=[]
        for start,end in zip(poly,poly[1:]+poly[:1]):
            sa=q(start)-limit;sb=q(end)-limit
            ia=sa>=-.000001 if greater else sa<=.000001
            ib=sb>=-.000001 if greater else sb<=.000001
            if ia:result.append(start)
            if ia!=ib:
                t=sa/(sa-sb)
                result.append((start[0]+(end[0]-start[0])*t,start[1]+(end[1]-start[1])*t))
        clean=[]
        for point in result:
            if not clean or math.dist(clean[-1],point)>1e-6:clean.append(point)
        if len(clean)>1 and math.dist(clean[0],clean[-1])<1e-6:clean.pop()
        return clean
    rectangle=[(y0,a),(y1,a),(y1,b),(y0,b)]
    lo=min(map(q,rectangle));hi=max(map(q,rectangle));cuts={lo,hi}
    if override is None and key!='nantes405':
        for period in range(-2,10):
            for band in range(7):
                at=period*8.15+1.35+band*.25
                if lo<at<hi:cuts.add(at)
    cuts=sorted(cuts)
    for low,high in zip(cuts,cuts[1:]):
        poly=clip(clip(rectangle,low,True),high,False)
        if len(poly)<3:continue
        area=abs(sum(u[0]*v[1]-u[1]*v[0] for u,v in zip(poly,poly[1:]+poly[:1])))*.5
        if area<1e-8:continue
        yy=sum(v[0] for v in poly)/len(poly);zz=sum(v[1] for v in poly)/len(poly)
        mat=override or paint(key,yy,global_centre+zz)
        vertices=[(side*(x(y) if callable(x) else x),y,z) for y,z in poly]
        mesh.face(vertices,mat,(side,0,0))


def shell(mesh,key,definition,length,ratio,global_centre,cab_front,cab_rear):
    a=-length*.5+(1.72 if cab_front else .14);b=length*.5-(1.72 if cab_rear else .14)
    doors=[(d['z_m']*ratio-length*.5,d.get('width_m',1.3)) for d in definition.get('doors',[])]
    wins=[(w['z0_m']*ratio-length*.5,w['z1_m']*ratio-length*.5) for w in definition.get('windows',[])]
    cuts=sorted({a,b,*[max(a,min(b,z)) for c,w in doors for z in [c-w*.5,c+w*.5]],*[max(a,min(b,z)) for r in wins for z in r]})
    levels=[.28,.32,.48,1.05,1.14,2.45,2.48,2.60,2.77]
    for side in [1,-1]:
        for za,zb in zip(cuts,cuts[1:]):
            z=(za+zb)*.5
            door=any(abs(z-c)<w*.5-.0001 for c,w in doors)
            window=any(x<z<y for x,y in wins)
            for y0,y1 in zip(levels,levels[1:]):
                if door and y0>=.32 and y1<=2.45:continue
                mat='glass' if window and y0>=1.05 and y1<=2.60 else None
                side_panel(mesh,key,side,za,zb,y0,y1,global_centre,mat)
            if window and not door:
                mesh.box((side*1.204,1.83,za+.025),(.026,1.53,.05),'frame')
                # One broad reflection shape; no highlights copied from photos.
                side_panel(mesh,key,side,za+.07,min(zb,za+.18),1.2,2.5,global_centre,'glass_reflection',1.207)
        # The painted ribbon wraps over the shoulder and the roof as mesh
        # material regions; no photographic projection and no overlay surface.
        roof_cuts={a,b}
        if key!='nantes405':
            for period in range(-2,10):
                for band in range(7):
                    at=period*8.15+1.35+band*.25-global_centre-.28*(3.08-1)
                    if a<at<b:roof_cuts.add(at)
        roof_cuts=sorted(roof_cuts)
        side_panel(mesh,key,side,a,b,2.77,3.08,global_centre,x=lambda y:1.20-(y-2.77)*.15/.31)
    for za,zb in zip(roof_cuts,roof_cuts[1:]):
            mat=paint(key,3.08,global_centre+(za+zb)*.5)
            mesh.face([(side*1.20,2.77,za),(side*1.05,3.08,za),(side*1.05,3.08,zb),(side*1.20,2.77,zb)],mat,(side,1,0))
    for za,zb in zip(roof_cuts,roof_cuts[1:]):
        mesh.box((0,3.08,(za+zb)*.5),(2.10,.045,zb-za),paint(key,3.08,global_centre+(za+zb)*.5))
    mesh.box((0,.27,(a+b)*.5),(2.22,.09,b-a),'skirt')
    return doors


def naolib_front(mesh,length,direction):
    """Dedicated X05 Nantes front: broad glazing, curved continuous light crown,
    full-width black honeycomb lamp panel, green apron and white cheek fairings.
    Reference: Commons 151228963 (detail), 200396073/200396076 (front/rear).
    No geometry template or lamp clusters borrowed from the Angers fronts.
    """
    end=direction*length*.5
    profile=[(.28,.96),(.36,.99),(.62,1),(1.28,1),(2.60,.98),(2.85,.95),(3.0,.89),(3.08,.81)]
    rake=[(.28,.10),(.62,0),(1.20,.01),(1.28,.015),(2.65,.29),(3.08,.52)]
    def width(y):return 1.2*lerp_curve(profile,y)
    def surface(x,y,offset=0):
        inset=lerp_curve(rake,y)+.38*(abs(x)/1.2)**2
        return (x,y,end-direction*inset+direction*offset)
    # (height, central half-width, crown sag at the ends, material above row).
    # These regions are disjoint faces, not superimposed coloured panels.
    rows=[(.28,1.03,0,'frame'),(.36,1.03,0,'teal'),(.60,1.025,0,'frame'),
          (.64,1.02,0,'frame'),(1.20,1.02,0,'teal'),(1.28,1.02,0,'glass'),
          (2.45,1.02,0,'glass'),(2.73,1.00,.025,'frame'),
          (2.78,.995,.045,'glass'),(2.975,.965,.09,'led'),
          (3.01,.955,.09,'frame'),(3.035,.94,.09,'porcelain'),(3.08,.90,.075,'porcelain')]
    ts=[-1,-.85,-.65,-.4,0,.4,.65,.85,1]
    def point(row,t):return surface(t*row[1],row[0]-row[2]*abs(t)**6)
    for lower,upper in zip(rows,rows[1:]):
        for ta,tb in zip(ts,ts[1:]):
            mat=lower[3]
            if mat=='glass' and 1.28<=lower[0]<2.73 and ta==-.65:mat='glass_reflection'
            mesh.face([point(lower,ta),point(upper,ta),point(upper,tb),point(lower,tb)],mat,(0,0,direction))
        for side in [-1,1]:
            outer0=surface(side*width(lower[0]),lower[0])
            outer1=surface(side*width(upper[0]),upper[0])
            mat='frame' if upper[0]<=.36 else 'porcelain'
            mesh.face([point(lower,side),point(upper,side),outer1,outer0],mat,(0,0,direction))
            side_mat='glass' if lower[0]>=1.28 and upper[0]<=2.78 else 'porcelain'
            if upper[0]<=.36:side_mat='frame'
            mesh.face([outer0,outer1,(side*1.2,upper[0],end-direction*1.72),
                       (side*1.2,lower[0],end-direction*1.72)],side_mat,(side,0,0))
    mesh.face([surface(-width(3.08),3.08),surface(width(3.08),3.08),
               (1.05,3.08,end-direction*1.72),(-1.05,3.08,end-direction*1.72)],'porcelain',(0,1,0))
    # Sixty-plus hexagonal lenses: large at the sides, smaller near the centre.
    # Reference rear view uses red optics; front uses white. Same modelled layout.
    cells=0
    for row in range(5):
        for column in range(14):
            x=(column-6.5)*.14+(row%2)*.07
            radius=.026+.039*min(1,max(0,(abs(x)-.18)/.55))
            if abs(x)+radius>1.005:continue
            y=.695+row*.109
            points=[surface(x+radius*math.cos(math.tau*k/6),y+radius*math.sin(math.tau*k/6),.018) for k in range(6)]
            mesh.face(points,'headlamp' if direction<0 else 'tail_lamp',(0,0,direction));cells+=1
    # One asymmetric pantograph-style wiper assembly, parked on the right.
    for delta in [0,.065]:
        mesh.tube(surface(direction*(.34+delta),1.30,.035),surface(direction*(.84+delta),2.08,.035),.012,'frame',6)
    mesh.tube(surface(direction*.82,1.94,.052),surface(direction*.96,2.46,.052),.023,'frame',6)
    return {'profile':'naolib_405','hexagonal_lenses_per_end':cells,
            'references':[151228963,200396073,200396076],
            'recognition_features':['broad_rounded_rectangle_glazing','continuous_curved_led_crown',
              'full_width_honeycomb_optics','white_cheeks','green_lower_apron','asymmetric_wiper_viewer_right']}


def front(mesh,key,length,direction,contour):
    # Reference-constrained low-poly patch layout. 10% sampled Meshy contour,
    # 90% explicit proportions from the reviewed train photographs. This is
    # local retopology/reconstruction, not another Meshy-generated model.
    if key=='nantes405':return naolib_front(mesh,length,direction)
    end=direction*length*.5
    profile=[(.28,.90),(.75,.99),(1.2,1),(2.2,.99),(2.75,.97),(2.96,.93),(3.08,.84)]
    rake=[(.28,.18),(.8,0),(1.13,.025),(2.0,.27),(2.8,.73),(3.08,1.02)]
    if key=='angers305':rake=[(.28,.15),(.8,0),(1.13,.02),(2,.23),(2.8,.59),(3.08,.88)]
    def width(y):return 1.2*lerp_curve(profile,y)*(.9+.1*lerp_curve(contour,y/3.08))
    def surface(x,y,offset=0):
        inset=lerp_curve(rake,y)+.42*(abs(x)/max(width(y),.1))**2
        return (x,y,end-direction*inset+direction*offset)
    shield=[(1.03,.64),(1.16,.79),(1.65,.88),(2.35,.90),(2.70,.88),(2.88,.81),(2.98,.64),(3.01,.47)]
    if key=='angers305':shield=[(1.03,.70),(1.20,.83),(1.8,.90),(2.45,.90),(2.79,.86),(2.96,.73),(3.01,.50)]
    shield=[(y,w*1.14) for y,w in shield]
    ys=sorted({.28,.48,.72,.9,1.08,1.14,1.28,1.65,2.0,2.35,2.6,2.8,2.96,3.08,*[r[0] for r in shield]})
    ts=[-1,-.90,-.72,-.45,0,.45,.72,.90,1]
    for y0,y1 in zip(ys,ys[1:]):
        is_glass=shield[0][0]<=y0 and y1<=shield[-1][0]
        if is_glass:
            m0=min(width(y0)-.035,lerp_curve(shield,y0));m1=min(width(y1)-.035,lerp_curve(shield,y1))
            for t0,t1 in zip(ts,ts[1:]):
                mat='glass_reflection' if t0==-.72 else 'glass'
                mesh.face([surface(t0*m0,y0),surface(t0*m1,y1),surface(t1*m1,y1),surface(t1*m0,y0)],mat,(0,0,direction))
            for side in [-1,1]:
                mesh.face([surface(side*m0,y0),surface(side*m1,y1),surface(side*width(y1),y1),surface(side*width(y0),y0)],'porcelain',(0,0,direction))
        else:
            for t0,t1 in zip(ts,ts[1:]):
                mesh.face([surface(t0*width(y0),y0),surface(t0*width(y1),y1),surface(t1*width(y1),y1),surface(t1*width(y0),y0)],'skirt' if y1<=.48 else 'porcelain',(0,0,direction))
        # Cab side glazing belongs to the cheek mesh, not an overlapping decal.
        for side in [-1,1]:
            mat='glass' if y0>=1.14 and y1<=2.6 else ('skirt' if y1<=.48 else 'porcelain')
            mesh.face([surface(side*width(y0),y0),surface(side*width(y1),y1),(side*1.2,y1,end-direction*1.72),(side*1.2,y0,end-direction*1.72)],mat,(side,0,0))
    mesh.face([surface(-width(3.08),3.08),surface(width(3.08),3.08),(1.05,3.08,end-direction*1.72),(-1.05,3.08,end-direction*1.72)],'porcelain',(0,1,0))
    for side in [-1,1]:
        lamp_x=[.86,.65,.45];lamp_y=.86
        for j,x in enumerate(lamp_x):
            p=surface(side*x,lamp_y+.13-.055*j,.025);q=(p[0],p[1],p[2]+direction*.016)
            mesh.tube(p,q,.091 if j==0 else .070,'steel',16)
            q2=(q[0],q[1],q[2]+direction*.006)
            mesh.tube(q,q2,.066 if j==0 else .050,'tail_lamp' if j==2 else 'headlamp',16)
    # The manufacturer mark sits within the black lower windscreen. A diagonal
    # wiper linkage replaces the generic pair of vertical bars.
    for delta in [0,.065]:
        mesh.tube(surface(direction*(-.12+delta),1.17,.04),surface(direction*(.65+delta),1.96,.04),.012,'frame',6)
    mesh.tube(surface(direction*.50,1.77,.055),surface(direction*.82,2.35,.055),.018,'frame',6)
    # Raised manufacturer's ring inside the black chin insert.
    for j in range(16):
        aa=math.tau*j/16;bb=math.tau*(j+1)/16
        mesh.face([surface(r*math.cos(angle),1.16+r*math.sin(angle),.008)
                   for r,angle in [(.043,aa),(.043,bb),(.035,bb),(.035,aa)]],
                  'porcelain',(0,0,direction))
    return {'profile':key,'references':[28965152,28980217] if key=='angers302' else [197513329,188202395],
            'recognition_features':['wide_arched_windscreen','inclined_three_lamp_clusters',
               'black_chin_badge','diagonal_wiper_linkage']}


def equipment(mesh,definition,length,ratio,roof_height):
    if definition.get('bogie',False):
        z=definition.get('bogie_z_m',definition['length_m']*.5)*ratio-length*.5
        mesh.box((0,.32,z),(1.85,.34,2.15),'frame')
        for side in [-1,1]:
            for d in [-.78,.78]:mesh.tube((side*.68,.30,z+d),(side*.88,.30,z+d),.30,'steel',16)
    for item in definition.get('roof',[]):
        z=item.get('z_m',0)*ratio-length*.5
        typ=item.get('type','box')
        if typ=='fairing':continue
        w,h,l=item.get('size',[1.4,.22,1.6]);l=min(l,length-.5)
        z=max(-length*.5+l*.5+.12,min(length*.5-l*.5-.12,z))
        if typ=='pantograph':
            for side in [-1,1]:
                for zz in [-.70,.70]:mesh.tube((side*.5,3.08,z+zz),(side*.5,roof_height+.20,z+zz),.055,'insulator',8)
                mesh.box((side*.5,roof_height+.20,z),(.065,.075,1.6),'steel')
            mesh.box((0,roof_height+.20,z+.76),(1.06,.075,.10),'steel')
        else:
            mesh.box((0,3.18,z),(min(w,1.85),.20,l),'roof')
            if typ=='hvac':
                for j in range(7):mesh.box((-.6+j*.2,3.285,z),(.035,.012,l*.78),'frame')


def gangway(mesh,length,front_end,rear_end):
    for direction,on in [(-1,not front_end),(1,not rear_end)]:
        if not on:continue
        for j in range(5):
            z=direction*(length*.5-.14+j*.028)
            width=2.10 if j%2 else 2.18
            for side in [-1,1]:mesh.box((side*(width*.5-.07),1.52,z),(.14,2.32,.020),'bellows' if j%2 else 'frame')
            mesh.box((0,2.66,z),(width,.13,.020),'bellows')
            mesh.box((0,.36,z),(width,.10,.020),'bellows')


def door(mesh,key,side,a,b,global_centre):
    x=side*1.23
    for y0,y1 in [(.32,.5),(.5,1.0),(1.0,2.30),(2.30,2.45)]:
        if y0>=1.0 and y1<=2.30:
            side_panel(mesh,key,side,a,b,y0,y1,global_centre,'glass',1.23)
            for z in [a+.025,b-.025]:mesh.box((x,1.65,z),(.025,1.30,.05),'porcelain')
        else:side_panel(mesh,key,side,a,b,y0,y1,global_centre,None,1.23)
    for z in [a,b]:mesh.box((x,1.385,z),(.045,2.13,.028),'frame')
    mesh.box((x,2.43,(a+b)*.5),(.045,.04,b-a),'frame')
    mesh.box((x,.36,(a+b)*.5),(.045,.04,b-a),'steel')
    # Door control and warning markers, matching the same palette as the body.
    mesh.box((x+side*.022,1.2,b-.10),(.025,.05,.05),'led')


def pantographs():
    parts=[]
    lower=Mesh('PantoLower')
    for side in [-1,1]:lower.box((side*.22,.5,0),(.05,1,.06),'frame')
    lower.box((0,.96,0),(.49,.045,.06),'steel');parts.append(lower.object())
    upper=Mesh('PantoUpper');upper.box((0,.5,0),(.045,1,.045),'frame');parts.append(upper.object())
    head=Mesh('PantoHead');head.box((0,.03,0),(1.34,.045,.11),'frame')
    for side in [-1,1]:head.box((side*.74,-.025,0),(.20,.025,.07),'steel')
    head.box((0,-.08,0),(.55,.055,.065),'frame');parts.append(head.object());return parts


def build(key,family,length,contour):
    plan=json.loads((ROOT/'data/rolling_stock/plans'/(family+'.json')).read_text());ratio=length/sum(m['length_m'] for m in plan['modules'])
    objects=[];position=0;leaf_index=0;report=[];front_details=None
    for i,definition in enumerate(plan['modules']):
        l=definition['length_m']*ratio;centre=position+l*.5
        first=i==0;last=i==len(plan['modules'])-1
        body=Mesh('Module%02d'%i)
        doors=shell(body,key,definition,l,ratio,centre,first,last)
        if first:front_details=front(body,key,l,-1,contour)
        if last:front(body,key,l,1,contour)
        equipment(body,definition,l,ratio,plan['height_m']);gangway(body,l,first,last)
        objects.append(body.object());report.append({'name':body.name,'length_m':l,'faces':len(body.f)})
        for d,(c,w) in zip(definition.get('doors',[]),doors):
            n=2 if key=='angers305' else int(d.get('leaves',2))
            for side in [1,-1]:
                for part in range(n):
                    a=c-w*.5+w*part/n+.01;b=c-w*.5+w*(part+1)/n-.01
                    leaf=Mesh('Door%03d'%leaf_index);door(leaf,key,side,a,b,centre);objects.append(leaf.object());leaf_index+=1
        position+=l
    objects+=pantographs()
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(OUT/(key+'_body.glb')),use_selection=True,export_format='GLB',export_yup=True,export_animations=False,export_cameras=False,export_lights=False)
    for obj in objects:bpy.data.objects.remove(obj,do_unlink=True)
    return {'status':'reference_facades_v3','modules':report,'doors':leaf_index,'photographic_textures':0,'legacy_visible_meshes':0,'original_meshy_triangles_retained':0,'front_details':front_details,'contour_source':'dedicated Naolib reference profile; no generic/Meshy front fit' if key=='nantes405' else 'recorded Meshy geometry; 10% width fit, reference-constrained reconstruction'}


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    contours={key:mesh_y_contour(key) for key in PROFILES}
    (OUT/'contour_study.json').write_text(json.dumps(contours,indent=2)+'\n')
    palette();report={}
    old=json.loads((OUT/'build_report.json').read_text())
    for key,(family,length) in PROFILES.items():
        report[key]=build(key,family,length,contours[key]);report[key]['seat']=old[key]['seat']
    (OUT/'build_report.json').write_text(json.dumps(report,indent=2)+'\n')

if __name__=='__main__':main()
