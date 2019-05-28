pico-8 cartridge // http://www.pico-8.com
version 18
__lua__
-- vector & tools
function make_v(a,b)
	return {
		b[1]-a[1],
		b[2]-a[2],
		b[3]-a[3]}
end
function v_clone(v)
	return {v[1],v[2],v[3]}
end
function v_dot(a,b)
	return a[1]*b[1]+a[2]*b[2]+a[3]*b[3]
end
function v_scale(v,scale)
	v[1]*=scale
	v[2]*=scale
	v[3]*=scale
end
function v_add(v,dv,scale)
	scale=scale or 1
	v[1]+=scale*dv[1]
	v[2]+=scale*dv[2]
	v[3]+=scale*dv[3]
end
function v_min(a,b)
	return {min(a[1],b[1]),min(a[2],b[2]),min(a[3],b[3])}
end
function v_max(a,b)
	return {max(a[1],b[1]),max(a[2],b[2]),max(a[3],b[3])}
end

local v_up={0,1,0}

-- matrix functions
function m_x_v(m,v)
	local x,y,z=v[1],v[2],v[3]
	v[1],v[2],v[3]=m[1]*x+m[5]*y+m[9]*z+m[13],m[2]*x+m[6]*y+m[10]*z+m[14],m[3]*x+m[7]*y+m[11]*z+m[15]
end

function make_m_from_euler(x,y,z)
		local a,b = cos(x),-sin(x)
		local c,d = cos(y),-sin(y)
		local e,f = cos(z),-sin(z)
  
  -- yxz order
  local ce,cf,de,df=c*e,c*f,d*e,d*f
	 return {
	  ce+df*b,a*f,cf*b-de,0,
	  de*b-cf,a*e,df+ce*b,0,
	  a*d,-b,a*c,0,
	  0,0,0,1}
end
-- only invert 3x3 part
function m_inv(m)
	m[2],m[5]=m[5],m[2]
	m[3],m[9]=m[9],m[3]
	m[7],m[10]=m[10],m[7]
end
function m_set_pos(m,v)
	m[13],m[14],m[15]=v[1],v[2],v[3]
end
-- returns basis vectors from matrix
function m_right(m)
	return {m[1],m[2],m[3]}
end
function m_up(m)
	return {m[5],m[6],m[7]}
end
function m_fwd(m)
	return {m[9],m[10],m[11]}
end

function make_plane(width)
	return {
		{0,0,0},
		{width,0,0},
		{width,0,width},
		{0,0,width}
	}
end

-- sort
-- https://github.com/morgan3d/misc/tree/master/p8sort
function sort(data)
 local n = #data 
 if(n<2) return
 
 -- form a max heap
 for i = flr(n / 2) + 1, 1, -1 do
  -- m is the index of the max child
  local parent, value, m = i, data[i], i + i
  local key = value.key 
  
  while m <= n do
   -- find the max child
   if ((m < n) and (data[m + 1].key > data[m].key)) m += 1
   local mval = data[m]
   if (key > mval.key) break
   data[parent] = mval
   parent = m
   m += m
  end
  data[parent] = value
 end 

 -- read out the values,
 -- restoring the heap property
 -- after each step
 for i = n, 2, -1 do
  -- swap root with last
  local value = data[i]
  data[i], data[1] = data[1], value

  -- restore the heap
  local parent, terminate, m = 1, i - 1, 2
  local key = value.key 
  
  while m <= terminate do
   local mval = data[m]
   local mkey = mval.key
   if (m < terminate) and (data[m + 1].key > mkey) then
    m += 1
    mval = data[m]
    mkey = mval.key
   end
   if (key > mkey) break
   data[parent] = mval
   parent = m
   m += m
  end  
  
  data[parent] = value
 end
end

-->8
-- main engine
local angles={}
function make_cam(x0,y0,focal)
	local angle=0
	for i=0,127 do
		add(angles,atan2(64,i-64))
	end
	return {
		pos={0,0,0},
		track=function(self,pos,a,m)
   			self.pos=v_clone(pos)
   			-- height
			v_add(self.pos,m_fwd(m),-1.5)
   			self.pos[2]+=1.5
			angle=a
			-- inverse view matrix
		   	m_inv(m)
   			self.m=m
  		end,
	 	project2d=function(self,x,y)
	 		return x*8,128-y*8
	 	end,
	 	project=function(self,v)
	  		-- view to screen
   			local w=focal/v[3]
   			return x0+ceil(v[1]*w),y0-ceil(v[2]*w),w
	 	end,
	visible_tiles=function(self)
  	local x,y=self.pos[1]/8+16,self.pos[3]/8+16
   local x0,y0=flr(x),flr(y)
   local tiles={
    [x0+32*y0]=true
   } 
   
   for i=1,128 do
   	
   	local a=angles[i]+angle
   	local v,u=cos(a),-sin(a)
   	
    local mapx,mapy=x0,y0
   
    local ddx,ddy=abs(1/u),abs(1/v)
    local mapdx,distx
    if u<0 then
    	mapdx=-1
     distx=(x-mapx)*ddx
    else
    	mapdx=1
     distx=(mapx+1-x)*ddx
    end
   	local mapdy,disty
    if v<0 then
    	mapdy=-1
     disty=(y-mapy)*ddy
    else
    	mapdy=1
     disty=(mapy+1-y)*ddy
    end	
    for dist=0,2 do
   		if distx<disty then
   			distx+=ddx
   			mapx+=mapdx
   		else
   			disty+=ddy
   			mapy+=mapdy
   		end
   		-- non solid visible tiles
   		if mapx>=0 and mapy>=0 and mapx<16 and mapy<16 then
   			tiles[mapx+32*mapy]=true
   		end
   	end				
  	end	
  	return tiles
	 end
	}
end

function make_plyr(p)
	local pos,angle=v_clone(p),0
	local oldf
	local velocity=0
	return {
		get_pos=function()
	 		return pos,angle,make_m_from_euler(0.1,angle,0)
		 end,
		handle_input=function()
			local dx,dy=0,0
			if(btn(2)) dx=1
			if(btn(3)) dx=-1
			if(btn(0)) dy=-1
			if(btn(1)) dy=1
		
			angle+=dy/64
			if(oldf) dx/=8
			velocity+=dx
		end,
		update=function()
  			velocity*=0.8

			-- update orientation matrix
			local m=make_m_from_euler(0,angle,0)
			v_add(pos,m_fwd(m),velocity/4)
			v_add(pos,v_up,-0.2)
			-- find ground
			local newf,newpos=find_face(pos,oldf)
			if newf then		
				pos[2]=max(pos[2],newpos[2])
				oldf=newf
			end
			-- above 0
			pos[2]=max(pos[2])
		end
	}
end

local cam=make_cam(63.5,63.5,32)
local plyr=make_plyr({0,32,0})
local plane=make_plane(8)
local all_models={}

local track

local dither_pat={0xffff,0x7fff,0x7fdf,0x5fdf,0x5f5f,0x5b5f,0x5b5e,0x5a5e,0x5a5a,0x1a5a,0x1a4a,0x0a4a,0x0a0a,0x020a,0x0208,0x0000}

function project_poly(p,c)
	if #p>2 then
		local x0,y0=cam:project(p[1])
		local x1,y1=cam:project(p[2])
		for i=3,#p do
			local x2,y2=cam:project(p[i])
		 trifill(x0,y0,x1,y1,x2,y2,c)
			x1,y1=x2,y2
		end
	end
end

function is_inside(p,f)
	local v,vi=track.v,f.vi
	local inside,p0=0,track.v[vi[#vi]]
	for i=1,#vi do
		local p1=v[vi[i]]
		if((p0[3]-p1[3])*(p[1]-p0[1])+(p1[1]-p0[1])*(p[3]-p0[3])>0) inside+=1
		p0=p1
	end
	if inside==#vi then
		-- intersection point
		local t=-v_dot(make_v(v[vi[1]],p),f.n)/f.n[2]
		p=v_clone(p)
		p[2]+=t
		return f,p
	end
end

function find_face(p,oldf)	
	-- same face as previous hit
	if oldf then
		local newf,newp=is_inside(p,oldf)
		if(newf) return newf,newp
	end
	-- voxel?
	local x,z=flr(p[1]/8+16),flr(p[3]/8+16)
	local faces=track.voxels[x+32*z]
	if faces then
		for _,f in pairs(faces) do
			if f!=oldf then
				local newf,newp=is_inside(p,f)
				if(newf) return newf,newp
			end
		end
	end
	-- not found
end

function _init()
	track=all_models["track"]	
end

function _update()
	plyr:handle_input()
	
	plyr:update()
	
	cam:track(plyr:get_pos())
end

local sessionid=0
local k_far,k_near=1,8
local z_near=0.05
local current_face

function collect_faces(faces,cam_pos,v_cache,out)
	for _,face in pairs(faces) do
		-- avoid overdraw for shared faces
		if (band(face.flags,1)!=0 or v_dot(face.n,cam_pos)>face.cp) and face.session!=sessionid then
			local z,outcode,verts=0,0,{}
			-- project vertices
			for _,vi in pairs(face.vi) do
				local a=v_cache(vi)
				z+=a[3]					
				outcode=bor(outcode,a[3]>z_near and k_far or k_near)
				verts[#verts+1]=a
			end			
			-- mix of near/far verts?
			if band(outcode,1)==1 then
				-- mix of near+far vertices?
				if(band(outcode,0x9)==9) verts=z_poly_clip(z_near,verts)
				if(#verts>2) out[#out+1]={key=64/z,c=face.c,v=verts}
			end
			face.session=sessionid	
		end
	end
end

function collect_model_faces(model,m,out)
 -- cam pos in object space
 local x,y,z=cam.pos[1]-m[4],cam.pos[2]-m[8],cam.pos[3]-m[12]
 local cam_pos={m[1]*x+m[2]*y+m[3]*z,m[5]*x+m[6]*y+m[7]*z,m[9]*x+m[10]*y+m[11]*z}

	local p={}
	local function v_cache(k)
		local a=p[k]
		if not a then
			a=v_clone(model.v[k])
			-- relative to world
			m_x_v(m,a)
			-- world to cam
			v_add(a,cam.pos,-1)
			m_x_v(cam.m,a)
			p[k]=a
		end
		return a
	end

	collect_faces(model.f,cam_pos,v_cache,out)
end


function _draw()
	sessionid+=1
	cls(12)
	--rectfill(0,24,127,127,7)

	local p={}
	local function v_cache(k)
		local a=p[k]
		if not a then
			-- world to cam
			a=make_v(cam.pos,track.v[k])
			m_x_v(cam.m,a)
			p[k]=a
		end
		return a
	end
 
	local tiles=cam:visible_tiles()

 for k,_ in pairs(tiles) do
	 local i,j=k%32,flr(k/32)
 	local offset={8*i-128,0,8*j-128}
 	local p0=v_clone(plane[4])
 	v_add(p0,offset)
 	v_add(p0,cam.pos,-1)
	 m_x_v(cam.m,p0)
 	local x0,y0,w0=cam:project(p0)
 	local faces=track.voxels[k]
	if faces then
		fillp() 
	else
		fillp(0xa5a5)
	end
	for k=1,4 do
		local p1=v_clone(plane[k])
		v_add(p1,offset)
		v_add(p1,cam.pos,-1)
		m_x_v(cam.m,p1)
			local x1,y1,w1=cam:project(p1)
			if w0>0 and w1>0 then
				line(x0,y0,x1,y1,11)
			end
			x0,y0,w0=x1,y1,w1
		end
		--if(faces) print(#faces,x0,y0-8,7)
	end
	fillp()
 

	local out={}
	-- get visible voxels
	--for k,_ in pairs(tiles) do
		for k,_ in pairs(track.voxels) do
		local faces=track.voxels[k]
		if faces then
			collect_faces(faces,cam.pos,v_cache,out)
		end 
	end
	
	-- player model
	local pos,angle,m=plyr:get_pos()
	m_set_pos(m,pos)
	collect_model_faces(all_models["car"].lods[1],m,out)

 sort(out)
	-- all poly are encoded with 2 colors
 	fillp(0xa5a5)
	for i=1,#out do
		local d=out[i]
		project_poly(d.v,d.c)
	end
	fillp()

	local px,py=cam:project2d(pos[1],pos[3])
	pset(px,py,9)
 
	local cpu=flr(1000*stat(1))/10
	cpu=cpu.." ▤"..stat(0).." █:"..#out.."\n"..cam.pos[1].."/"..cam.pos[3]
	print(cpu,2,3,5)
	print(cpu,2,2,7)

end

-->8
-- unpack data & models
local cart_id,mem=1
function mpeek()
	if mem==0x4300 then
		printh("switching cart: "..cart_id)
		reload(0,0,0x4300,"track_"..cart_id..".p8")
		cart_id += 1
		mem=0
	end
	local v=peek(mem)
	mem+=1
	return v
end

-- unpack a list into an argument list
-- trick from: https://gist.github.com/josefnpat/bfe4aaa5bbb44f572cd0
function munpack(t, from, to)
 local from,to=from or 1,to or #t
 if(from<=to) return t[from], munpack(t, from+1, to)
end

-- w: number of bytes (1 or 2)
function unpack_int(w)
  	w=w or 1
	local i=w==1 and mpeek() or bor(shl(mpeek(),8),mpeek())
	return i
end
-- unpack 1 or 2 bytes
function unpack_variant()
	local h=mpeek()
	-- above 127?
	if band(h,0x80)>0 then
		h=bor(shl(band(h,0x7f),8),mpeek())
	end
	return h
end
-- unpack a float from 1 byte
function unpack_float(scale)
	local f=shr(unpack_int()-128,5)
	return f*(scale or 1)
end
-- unpack a double from 2 bytes
function unpack_double(scale)
	local f=(unpack_int(2)-16384)/128
	return f*(scale or 1)
end
-- unpack an array of bytes
function unpack_array(fn)
	for i=1,unpack_variant() do
		fn(i)
	end
end
-- valid chars for model names
local itoa='_0123456789abcdefghijklmnopqrstuvwxyz'
function unpack_string()
	local s=""
	unpack_array(function()
		local c=unpack_int()
		s=s..sub(itoa,c,c)
	end)
	return s
end

function unpack_model(model,scale)
	-- vertices
	unpack_array(function()
		local v={unpack_double(scale),unpack_double(scale),unpack_double(scale)}
		add(model.v,v)
	end)

	-- faces
	unpack_array(function()
		local f={vi={},flags=unpack_int(),c=unpack_int()}
		-- vertex indices
		-- quad?
		local n=band(f.flags,2)>0 and 4 or 3
		for i=1,n do
			add(f.vi,unpack_variant())
		end	
		-- inner faces?
		if band(f.flags,8)>0 then
			f.inner={}
			unpack_array(function()
				local df={vi={},flags=unpack_int(),c=unpack_int()}
				-- vertex indices
				-- quad?
				local n=band(df.flags,2)>0 and 4 or 3
				for i=1,n do
					add(df.vi,unpack_variant())
				end
				add(f.inner,df)
			end)
		end
		add(model.f,f)
	end)

	-- normals + n.p cache
	for i=1,#model.f do
		local f=model.f[i]
		f.n={unpack_float(),unpack_float(),unpack_float()}
		f.cp=v_dot(f.n,model.v[f.vi[1]])
	end
end
function unpack_models()
	mem=0x1000
	-- for all models
	unpack_array(function()
  local model,name,scale={lods={},lod_dist={}},unpack_string(),1/unpack_int()
				
		unpack_array(function()
			local d=unpack_double()
			assert(d<127,"lod distance too large:"..d)
			-- store square distance
			add(model.lod_dist,d*d)
		end)
  
		-- level of details models
		unpack_array(function()
			local lod={v={},f={},n={},cp={}}
			unpack_model(lod,0.1)
			add(model.lods,lod)
		end)

		-- index by name
		all_models[name]=model
	end)
end

-- unpack multi-cart track
function unpack_track()
	mem=0
	local model,name,scale={v={},f={},n={},cp={},voxels={}},unpack_string(),1/unpack_int()
	-- vertices + faces + normal data
	unpack_model(model)

	-- voxels: collision and rendering optimization
	unpack_array(function()
		local id,faces=unpack_variant(),{}
		unpack_array(function()
			add(faces,model.f[unpack_variant()])
		end)
		model.voxels[id]=faces
	end)
	-- index by name
	all_models[name]=model
end

-- track
reload(0,0,0x4300,"track_0.p8")
unpack_track()
-- restore cart
reload()
-- load regular 3d models
unpack_models()

-->8
-- trifill & clipping
-- by @p01
function p01_trapeze_h(l,r,lt,rt,y0,y1)
  lt,rt=(lt-l)/(y1-y0),(rt-r)/(y1-y0)
  if(y0<0)l,r,y0=l-y0*lt,r-y0*rt,0
   for y0=y0,min(y1,128) do
   rectfill(l,y0,r,y0)
   l+=lt
   r+=rt
  end
end
function p01_trapeze_w(t,b,tt,bt,x0,x1)
 tt,bt=(tt-t)/(x1-x0),(bt-b)/(x1-x0)
 if(x0<0)t,b,x0=t-x0*tt,b-x0*bt,0
 for x0=x0,min(x1,128) do
  rectfill(x0,t,x0,b)
  t+=tt
  b+=bt
 end
end

function trifill(x0,y0,x1,y1,x2,y2,col)
 color(col)
 if(y1<y0)x0,x1,y0,y1=x1,x0,y1,y0
 if(y2<y0)x0,x2,y0,y2=x2,x0,y2,y0
 if(y2<y1)x1,x2,y1,y2=x2,x1,y2,y1
 if max(x2,max(x1,x0))-min(x2,min(x1,x0)) > y2-y0 then
  col=x0+(x2-x0)/(y2-y0)*(y1-y0)
  p01_trapeze_h(x0,x0,x1,col,y0,y1)
  p01_trapeze_h(x1,col,x2,x2,y1,y2)
 else
  if(x1<x0)x0,x1,y0,y1=x1,x0,y1,y0
  if(x2<x0)x0,x2,y0,y2=x2,x0,y2,y0
  if(x2<x1)x1,x2,y1,y2=x2,x1,y2,y1
  col=y0+(y2-y0)/(x2-x0)*(x1-x0)
  p01_trapeze_w(y0,y0,y1,col,x0,x1)
  p01_trapeze_w(y1,col,y2,y2,x1,x2)
 end
end

--[[
function trifill(x0,y0,x1,y1,x2,y2,col)
	line(x0,y0,x1,y1,col)
	line(x2,y2)
	line(x0,y0)
end
]]

-- clipping
function plane_poly_clip(n,v)
	local dist,allin={},0
	for i,a in pairs(v) do
		local d=n[4]-(a[1]*n[1]+a[2]*n[2]+a[3]*n[3])
		if(d>0) allin+=1
	 dist[i]=d
	end
 -- early exit
	if(allin==#v) return v
 if(allin==0) return {}

	local res={}
	local v0,d0,v1,d1,t,r=v[#v],dist[#v]
 -- use local closure
 local clip_line=function()
 	local r,t=make_v(v0,v1),d0/(d0-d1)
 	v_scale(r,t)
 	v_add(r,v0)
 	res[#res+1]=r
 end
	for i=1,#v do
		v1,d1=v[i],dist[i]
		if d1>0 then
			if(d0<=0) clip_line()
			res[#res+1]=v1
		elseif d0>0 then
   clip_line()
		end
		v0,d0=v1,d1
	end
	return res
end

function z_poly_clip(znear,v)
	local dist={}
	for i,a in pairs(v) do
		dist[#dist+1]=-znear+a[3]
	end

	local res={}
	local v0,d0,v1,d1,t,r=v[#v],dist[#v]
 -- use local closure
 local clip_line=function()
 	local r,t=make_v(v0,v1),d0/(d0-d1)
 	v_scale(r,t)
 	v_add(r,v0)
 	res[#res+1]=r
 end
	for i=1,#v do
		v1,d1=v[i],dist[i]
		if d1>0 then
			if(d0<=0) clip_line()
			res[#res+1]=v1
		elseif d0>0 then
   clip_line()
		end
		v0,d0=v1,d1
	end
	return res
end

__gfx__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1030e0c0d11010050010b614c50454348a14c5047d244814c50422244814c50422348ae34a0422348ae34a04222448e34a047d2448e34a0454348a044e04e9c3
09044e0408b3ea044e14ebb3ea044e14ebc309f3c114ebb3ea046e046dc309f3a1046dc309f3a11448b3ea046e1448b3ea046e1448c309f3a11448c309f3c114
ebc309f3c10408b3eaf3c104e9c309046e046db3eaf3a1046db3eae3c1040804bde3c114f014e2e37e14f0142de37e14f014e2e3c1f31f14e2e37ef31f142de3
7e040804bde37ef31f14e2e3c1f31f142de37e04082452e3c104082452e3c114f0142df30804cbe3cbf34d14a6e389040804cbe3cb04d404ec04db0400048334
09e32b0439e36904a804010443040b0401d343f3050401d34314e40439e369e3ed044af34904c70425c360f3000428d38914e40401e3c8e32b0401e3c8142204
4af349e3ed0401f349f36704010443f3f904ec044304e11428f398f368045cf398f3fa0409d343f3000401d338f3480425c36014000428d389041604ec044304
150409d343f32e1428f39804a7045cf39804001422d3c604c214a6e389f33b04ec04db14220401f349040004b8b30f14000401d338144e040804bd144e14f014
e2149114f0142d149114f014e2144ef31f14e21491f31f142d1491040804bd1491f31f14e2144ef31f142d149104082452144e04082452144e14f0142de3c104
08b3bde3c114f0c3e2e37e14f0c32de37e14f0c3e2e3c1f31fc3e2e37ef31fc32de37e0408b3bde37ef31fc3e2e3c1f31fc32de37e0408d352e3c10408d352e3
c114f0c32d144e0408b3bd144e14f0c3e2149114f0c32d149114f0c3e2144ef31fc3e21491f31fc32d14910408b3bd1491f31fc3e2144ef31fc32d14910408d3
52144e0408d352144e14f0c32d75301110203040301150607080208890a0b0c0208841d051613082e07181f03022011121312000a14232912000a191f1c12000
b1c1f12220003212d191205591d102f12000e122f1022000d112e1022055123222e120003242b122205542a1c1b10066f372340011448292005592b2630022e2
43e30022a252732055b333237420555363b254205574c2d2b30082c364a3008803c2f32066e2d374232066235443e22066a2f25333206633b313a200610364c3
2022a213a352205554233353002273f2a2205554b2e3432055f273635320666373449220668314930420669282e3b22088a313b3d20082f364030088a3d2c320
55c3d2c2032088c274d3f32055931482440022e2e372202272f3d3e2006652a362008224a364008264f3242022830462340088346224206634721483008824f3
3420665262049300882462a3302230605040200094842535200094b4e4842000a415e4b420002584c405205584e4f4c42000d4f4e4152000c4f4d405205505d4
152520002515a435205535a4b494200055f5e54520005545a57520006575a5d52000e5c5854520554585b5a5200095d5a5b5200085c595b52055c5e5d5952000
e5f565d52055f555756520001606a6b62000163666062000269666362000a60646862055066676462000567666962000467656862055865696a62000a69626b6
2055b6263616750a08080608080608080a0808080608080a080608080809460a08080608080807460a08080806080807c90809c9080a08d9d8b708f978080618
68f9f7a7f9f708060808060808060827d9c7a93908f918770a0858060858161877085726b7f9c7080608a7f9f7693879a6387916785808080af97858e69876e8
d9c7663908081697299876080af768f9f758f9c736d8b7661997a91997080ad708f997d9e808a9198736e8086619870806080a08080809460608080a08080807
460608080806080807c90809c9080a080608080809460a08080608080807460a08080806080807c90809c9080a080a08080809460608080a0808080746060808
0806080807c90809c9080a08
