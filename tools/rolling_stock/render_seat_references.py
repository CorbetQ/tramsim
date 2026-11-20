import bpy,math,os
from pathlib import Path
from mathutils import Vector
OUT=Path(__file__).resolve().parents[2] / 'meshy_output/interior_inputs';OUT.mkdir(exist_ok=True)
def mat(name,col,metal=0):
 m=bpy.data.materials.new(name);m.diffuse_color=(*col,1);m.use_nodes=True;p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*col,1);p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=.48;return m
def box(name,loc,scale,m,bevel=.035):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.name=name;o.dimensions=scale;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(m)
 if bevel:mod=o.modifiers.new('Rounded manufactured edges','BEVEL');mod.width=bevel;mod.segments=3;mod=o.modifiers.new('Normals','WEIGHTED_NORMAL')
 return o
def tube(a,b,m,r=.015):
 v=Vector(b)-Vector(a);bpy.ops.mesh.primitive_cylinder_add(vertices=12,radius=r,depth=v.length,location=(Vector(a)+Vector(b))*.5);o=bpy.context.object;o.rotation_euler=v.to_track_quat('Z','Y').to_euler();o.data.materials.append(m)
for key in ['angers302','angers305','nantes405']:
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
 green=mat('Irigo lime upholstery',(.52,.68,.05));white=mat('Light grey seat shell',(.82,.85,.81));steel=mat('Brushed steel',(.45,.49,.5),.8);wood=mat('Nantes pale plywood',(.76,.65,.46));pad=mat('Nantes charcoal wool',(.055,.085,.10))
 n=2 if key=='nantes405' else 1
 for i in range(n):
  x=(i-(n-1)*.5)*.47
  if key=='nantes405':
   box('Plywood seat shell',(x,0,.48),(.46,.48,.055),wood,.025);back=box('Plywood back',(x,.205,.81),(.46,.055,.61),wood,.045);back.rotation_euler.x=math.radians(5)
   box('Dark back cushion',(x,.164,.83),(.37,.035,.45),pad,.045);box('Dark seat cushion',(x,-.02,.52),(.39,.38,.035),pad,.035)
  else:
   box('Moulded grey shell',(x,0,.45),(.46,.50,.055),white);back=box('Moulded back shell',(x,.21,.79),(.46,.065,.61),white,.055);back.rotation_euler.x=math.radians(6)
   box('Green fabric cushion',(x,-.015,.49),(.43,.44,.075),green);back=box('Green fabric back',(x,.165,.81),(.43,.06,.55),green,.05);back.rotation_euler.x=math.radians(6)
   # Fine contour seams are deliberately added locally, not inferred from low-res photos.
  tube((x,0,.1),(x,0,.43),steel,.028)
 tube((-.18 if n==1 else -.42,-.16,.09),(.18 if n==1 else .42,-.16,.09),steel,.022)
 camera_data=bpy.data.cameras.new('Camera');cam=bpy.data.objects.new('Camera',camera_data);bpy.context.collection.objects.link(cam);cam.location=(1.8,-2.8,1.8);target=Vector((0,0,.58));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();camera_data.type='ORTHO';camera_data.ortho_scale=1.55 if n==2 else 1.3;bpy.context.scene.camera=cam
 for loc,energy,size in [((2,-3,4),220,4),((-2,-1,2),100,3)]:
  ld=bpy.data.lights.new('Softbox','AREA');lo=bpy.data.objects.new('Softbox',ld);bpy.context.collection.objects.link(lo);lo.location=loc;lo.rotation_euler=(target-lo.location).to_track_quat('-Z','Y').to_euler();ld.energy=energy;ld.shape='DISK';ld.size=size
 s=bpy.context.scene;s.render.engine='CYCLES';s.cycles.samples=16;s.cycles.use_denoising=False;s.render.resolution_x=640;s.render.resolution_y=640;s.render.resolution_percentage=100;s.world.color=(.4,.4,.4);s.render.film_transparent=False;s.view_settings.view_transform='Standard';s.render.image_settings.file_format='PNG';s.render.filepath=str(OUT/(key+'.png'));bpy.ops.render.render(write_still=True)
 bpy.ops.wm.save_as_mainfile(filepath=str(OUT/(key+'.blend')))
