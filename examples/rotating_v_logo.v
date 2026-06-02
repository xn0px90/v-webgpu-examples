module main

#flag darwin examples/webgpu_macos_bridge.m

import math
import time
import sokol.sapp
import webgpu

const win_w = 960
const win_h = 640

struct Vec2 {
	x f32
	y f32
}

struct Vertex {
	x f32
	y f32
	r f32
	g f32
	b f32
	a f32
}

struct Uniforms {
	angle      f32
	pad0       [3]f32
	center     [2]f32
	resolution [2]f32
	tint       [4]f32
}

struct App {
mut:
	instance        webgpu.WGPUInstance
	adapter         webgpu.WGPUAdapter
	device          webgpu.WGPUDevice
	queue           webgpu.WGPUQueue
	surface         webgpu.WGPUSurface
	surface_format  webgpu.WGPUTextureFormat
	shader_module   webgpu.WGPUShaderModule
	pipeline_layout webgpu.WGPUPipelineLayout
	bind_layout     webgpu.WGPUBindGroupLayout
	bind_group      webgpu.WGPUBindGroup
	pipeline        webgpu.WGPURenderPipeline
	vertex_buffer   webgpu.WGPUBuffer
	uniform_buffer  webgpu.WGPUBuffer
	vertex_count    u32
	surface_width   int
	surface_height  int
	angle           f32
	last_tick       i64
	ready           bool
}

__global g_app = &App{}

fn on_adapter(adapter_status int, adapter_device voidptr, message &i8, userdata voidptr) {
	_ = message
	_ = userdata
	mut app := unsafe { g_app }
	if adapter_status != 0 {
		eprintln('webgpu: adapter request failed with status ${adapter_status}')
		sapp.request_quit()
		return
	}

	app.adapter = adapter_device
	app.surface_format = webgpu.wgpusurfacegetpreferredformat(app.surface, adapter_device)
	if app.surface_format == .wgputextureformat_undefined {
		app.surface_format = .wgputextureformat_bgra8unorm
	}

	device_desc := webgpu.WGPUDeviceDescriptor{
		next_in_chain: unsafe { nil }
		label: unsafe { nil }
		required_feature_count: 0
		required_features: unsafe { nil }
		require_limits: unsafe { nil }
		default_queue: webgpu.WGPUQueueDescriptor{
			next_in_chain: unsafe { nil }
			label: unsafe { nil }
		}
	}
	webgpu.wgpuadapterrequestdevice(adapter_device, &device_desc, on_device, userdata)
}

fn on_device(device_status int, device_handle voidptr, message &i8, userdata voidptr) {
	_ = message
	_ = userdata
	mut app := unsafe { g_app }
	if device_status != 0 {
		eprintln('webgpu: device request failed with status ${device_status}')
		sapp.request_quit()
		return
	}

	app.device = device_handle
	app.queue = webgpu.wgpudevicegetqueue(device_handle)
	app.resize_surface(sapp.width(), sapp.height())
	app.build_resources()
	app.ready = true
}

fn C.webgpu_macos_main_window_metal_layer() voidptr

fn main() {
	g_app.last_tick = time.ticks()
	sapp.run(&sapp.Desc{
		width:        win_w
		height:       win_h
		high_dpi:     true
		window_title: c'v-webgpu visual test: rotating V logo'
		init_cb:      init
		frame_cb:     frame
		event_cb:     event
		cleanup_cb:   cleanup
	})
}

fn event(e &sapp.Event) {
	if e.type == .key_down && e.key_code == .escape {
		sapp.request_quit()
	}
}

fn init() {
	mut app := unsafe { g_app }
	$if macos {
		app.instance = webgpu.wgpucreateinstance(unsafe { nil })
		if app.instance == unsafe { nil } {
			eprintln('webgpu: failed to create instance')
			sapp.request_quit()
			return
		}

		layer := C.webgpu_macos_main_window_metal_layer()
		if layer == unsafe { nil } {
			eprintln('webgpu: failed to get the macOS Metal layer')
			sapp.request_quit()
			return
		}

		layer_desc := webgpu.WGPUSurfaceDescriptorFromMetalLayer{
			chain: webgpu.WGPUChainedStruct{
				next: unsafe { nil }
				s_type: .wgpustype_surfacedescriptorfrommetallayer
			}
			layer: layer
		}
		surface_desc := webgpu.WGPUSurfaceDescriptor{
			next_in_chain: &layer_desc.chain
			label: unsafe { nil }
		}
		app.surface = webgpu.wgpuinstancecreatesurface(app.instance, &surface_desc)
		if app.surface == unsafe { nil } {
			eprintln('webgpu: failed to create a surface from the Metal layer')
			sapp.request_quit()
			return
		}

		options := webgpu.WGPURequestAdapterOptions{
			next_in_chain: unsafe { nil }
			power_preference: .wgpupowerpreference_highperformance
			backend_type: .wgpubackendtype_undefined
			force_fallback_adapter: 0
			compatible_surface: app.surface
		}
		webgpu.wgpuinstancerequestadapter(app.instance, &options, on_adapter, unsafe { nil })
	} $else {
		eprintln('This example currently targets macOS because it uses the Cocoa/Metal window from sokol.app.')
		sapp.request_quit()
	}
}

fn cleanup() {
	mut app := unsafe { g_app }
	if app.ready {
		webgpu.wgpubindgrouprelease(app.bind_group)
		webgpu.wgpubindgrouplayoutrelease(app.bind_layout)
		webgpu.wgpurenderpipelinerelease(app.pipeline)
		webgpu.wgpushadermodulerelease(app.shader_module)
		webgpu.wgpupipelinelayoutrelease(app.pipeline_layout)
		webgpu.wgpubufferrelease(app.vertex_buffer)
		webgpu.wgpubufferrelease(app.uniform_buffer)
		webgpu.wgpuqueuerelease(app.queue)
		webgpu.wgpudevicerelease(app.device)
		webgpu.wgpusurfacerelease(app.surface)
		webgpu.wgpuinstancerelease(app.instance)
	}
}

fn frame() {
	mut app := unsafe { g_app }
	if !app.ready {
		return
	}

	now := time.ticks()
	dt := f32(now - app.last_tick) / 1000.0
	app.last_tick = now
	app.angle += dt * 1.4

	cur_w := sapp.width()
	cur_h := sapp.height()
	if cur_w != app.surface_width || cur_h != app.surface_height {
		app.resize_surface(cur_w, cur_h)
	}

	mut surface_texture := webgpu.WGPUSurfaceTexture{}
	webgpu.wgpusurfacegetcurrenttexture(app.surface, &surface_texture)
	if surface_texture.status != .wgpusurfacegetcurrenttexturestatus_success {
		if surface_texture.status == .wgpusurfacegetcurrenttexturestatus_outdated || surface_texture.status == .wgpusurfacegetcurrenttexturestatus_lost {
			app.resize_surface(cur_w, cur_h)
		}
		if surface_texture.status == .wgpusurfacegetcurrenttexturestatus_outofmemory || surface_texture.status == .wgpusurfacegetcurrenttexturestatus_devicelost {
			eprintln('webgpu: surface texture acquisition failed with status ${surface_texture.status}')
			sapp.request_quit()
		}
		return
	}

	texture_view := webgpu.wgputexturecreateview(surface_texture.texture, &webgpu.WGPUTextureViewDescriptor{})
	encoder := webgpu.wgpudevicecreatecommandencoder(app.device, &webgpu.WGPUCommandEncoderDescriptor{
		next_in_chain: unsafe { nil }
		label: unsafe { nil }
	})

	color_attachment := webgpu.WGPURenderPassColorAttachment{
		next_in_chain: unsafe { nil }
		view: texture_view
		resolve_target: unsafe { nil }
		load_op: .wgpuloadop_clear
		store_op: .wgpustoreop_store
		clear_value: webgpu.WGPUColor{
			r: 0.039
			g: 0.055
			b: 0.09
			a: 1.0
		}
	}
	pass_desc := webgpu.WGPURenderPassDescriptor{
		next_in_chain: unsafe { nil }
		label: unsafe { nil }
		color_attachment_count: 1
		color_attachments: &color_attachment
		depth_stencil_attachment: unsafe { nil }
		occlusion_query_set: unsafe { nil }
		timestamp_writes: unsafe { nil }
	}
	pass := webgpu.wgpucommandencoderbeginrenderpass(encoder, &pass_desc)
	webgpu.wgpurenderpassencodersetpipeline(pass, app.pipeline)
	webgpu.wgpurenderpassencodersetbindgroup(pass, 0, app.bind_group, 0, unsafe { nil })
	webgpu.wgpurenderpassencoderdraw(pass, app.vertex_count, 1, 0, 0)
	webgpu.wgpurenderpassencoderend(pass)

	cmd := webgpu.wgpucommandencoderfinish(encoder, &webgpu.WGPUCommandBufferDescriptor{
		next_in_chain: unsafe { nil }
		label: unsafe { nil }
	})
	webgpu.wgpuqueuesubmit(app.queue, 1, &cmd)
	webgpu.wgpusurfacepresent(app.surface)

	webgpu.wgputexturerelease(surface_texture.texture)
	webgpu.wgputextureviewrelease(texture_view)
	webgpu.wgpucommandbufferrelease(cmd)
	webgpu.wgpucommandencoderrelease(encoder)

	uniforms := Uniforms{
		angle: app.angle
		center: [2]f32{ f32(cur_w) * 0.5, f32(cur_h) * 0.5 }
		resolution: [2]f32{ f32(cur_w), f32(cur_h) }
		tint: [4]f32{ 1.0, 1.0, 1.0, 1.0 }
	}
	webgpu.wgpuqueuewritebuffer(app.queue, app.uniform_buffer, 0, &uniforms, sizeof(Uniforms))
}

fn (mut app App) resize_surface(width int, height int) {
	if width <= 0 || height <= 0 {
		return
	}
	app.surface_width = width
	app.surface_height = height
	config := webgpu.WGPUSurfaceConfiguration{
		next_in_chain: unsafe { nil }
		device: app.device
		format: app.surface_format
		usage: u32(webgpu.wgputextureusage_renderattachment)
		view_format_count: 0
		view_formats: unsafe { nil }
		alpha_mode: .wgpucompositealphamode_opaque
		width: u32(width)
		height: u32(height)
		present_mode: .wgpupresentmode_fifo
	}
	webgpu.wgpusurfaceconfigure(app.surface, &config)
}

fn (mut app App) build_resources() {
	vertices := build_logo_mesh()
	app.vertex_count = u32(vertices.len)

	vertex_bytes := usize(vertices.len * int(sizeof(Vertex)))
	app.vertex_buffer = webgpu.wgpudevicecreatebuffer(app.device, &webgpu.WGPUBufferDescriptor{
		next_in_chain: unsafe { nil }
		label: c'logo-vertices'
		usage: u32(webgpu.wgpubufferusage_vertex | webgpu.wgpubufferusage_copydst)
		size: u64(vertex_bytes)
		mapped_at_creation: 0
	})
	webgpu.wgpuqueuewritebuffer(app.queue, app.vertex_buffer, 0, vertices.data, vertex_bytes)

	app.uniform_buffer = webgpu.wgpudevicecreatebuffer(app.device, &webgpu.WGPUBufferDescriptor{
		next_in_chain: unsafe { nil }
		label: c'logo-uniforms'
		usage: u32(webgpu.wgpubufferusage_uniform | webgpu.wgpubufferusage_copydst)
		size: u64(sizeof(Uniforms))
		mapped_at_creation: 0
	})

	bind_layout_entries := [webgpu.WGPUBindGroupLayoutEntry{
		next_in_chain: unsafe { nil }
		binding: 0
		visibility: u32(webgpu.WGPUShaderStage.wgpushaderstage_vertex)
		buffer: webgpu.WGPUBufferBindingLayout{
			next_in_chain: unsafe { nil }
			type_: .wgpubufferbindingtype_uniform
			has_dynamic_offset: 0
			min_binding_size: u64(sizeof(Uniforms))
		}
		sampler: webgpu.WGPUSamplerBindingLayout{}
		texture: webgpu.WGPUTextureBindingLayout{}
		storage_texture: webgpu.WGPUStorageTextureBindingLayout{}
	}]
	app.bind_layout = webgpu.wgpudevicecreatebindgrouplayout(app.device, &webgpu.WGPUBindGroupLayoutDescriptor{
		next_in_chain: unsafe { nil }
		label: c'logo-bind-layout'
		entry_count: bind_layout_entries.len
		entries: bind_layout_entries.data
	})

	pipeline_layouts := [app.bind_layout]
	app.pipeline_layout = webgpu.wgpudevicecreatepipelinelayout(app.device, &webgpu.WGPUPipelineLayoutDescriptor{
		next_in_chain: unsafe { nil }
		label: c'logo-pipeline-layout'
		bind_group_layout_count: pipeline_layouts.len
		bind_group_layouts: pipeline_layouts.data
	})

	shader_src := [
		'struct Uniforms {',
		'  angle: f32,',
		'  _pad0: vec3<f32>,',
		'  center: vec2<f32>,',
		'  resolution: vec2<f32>,',
		'  tint: vec4<f32>,',
		'};',
		'@group(0) @binding(0) var<uniform> u: Uniforms;',
		'struct VsIn { @location(0) position: vec2<f32>, @location(1) color: vec4<f32>, };',
		'struct VsOut { @builtin(position) position: vec4<f32>, @location(0) color: vec4<f32>, };',
		'@vertex fn vs_main(input: VsIn) -> VsOut {',
		'  let s = sin(u.angle);',
		'  let c = cos(u.angle);',
		'  let rotated = vec2<f32>(input.position.x * c - input.position.y * s, input.position.x * s + input.position.y * c);',
		'  let world = rotated + u.center;',
		'  var out: VsOut;',
		'  out.position = vec4<f32>(world.x / u.resolution.x * 2.0 - 1.0, 1.0 - world.y / u.resolution.y * 2.0, 0.0, 1.0);',
		'  out.color = input.color * u.tint;',
		'  return out;',
		'}',
		'@fragment fn fs_main(input: VsOut) -> @location(0) vec4<f32> {',
		'  return input.color;',
		'}',
	].join('\n')
	wgsl_desc := webgpu.WGPUShaderModuleWGSLDescriptor{
		chain: webgpu.WGPUChainedStruct{
			next: unsafe { nil }
			s_type: .wgpustype_shadermodulewgsldescriptor
		}
		code: &i8(shader_src.str)
	}
	app.shader_module = webgpu.wgpudevicecreateshadermodule(app.device, &webgpu.WGPUShaderModuleDescriptor{
		next_in_chain: &wgsl_desc.chain
		label: c'logo-shader'
		hint_count: 0
		hints: unsafe { nil }
	})

	vertex_attributes := [
		webgpu.WGPUVertexAttribute{ format: .wgpuvertexformat_float32x2, offset: 0, shader_location: 0 },
		webgpu.WGPUVertexAttribute{ format: .wgpuvertexformat_float32x4, offset: 8, shader_location: 1 },
	]
	vertex_layouts := [webgpu.WGPUVertexBufferLayout{
		array_stride: u64(sizeof(Vertex))
		step_mode: .wgpuvertexstepmode_vertex
		attribute_count: vertex_attributes.len
		attributes: vertex_attributes.data
	}]
	color_targets := [webgpu.WGPUColorTargetState{
		next_in_chain: unsafe { nil }
		format: app.surface_format
		blend: unsafe { nil }
		write_mask: u32(webgpu.WGPUColorWriteMask.wgpucolorwritemask_all)
	}]
	vertex_state := webgpu.WGPUVertexState{
		next_in_chain: unsafe { nil }
		module_: app.shader_module
		entry_point: c'vs_main'
		constant_count: 0
		constants: unsafe { nil }
		buffer_count: vertex_layouts.len
		buffers: vertex_layouts.data
	}
	fragment_state := webgpu.WGPUFragmentState{
		next_in_chain: unsafe { nil }
		module_: app.shader_module
		entry_point: c'fs_main'
		constant_count: 0
		constants: unsafe { nil }
		target_count: color_targets.len
		targets: color_targets.data
	}
	app.pipeline = webgpu.wgpudevicecreaterenderpipeline(app.device, &webgpu.WGPURenderPipelineDescriptor{
		next_in_chain: unsafe { nil }
		label: c'logo-pipeline'
		layout: app.pipeline_layout
		vertex: vertex_state
		primitive: webgpu.WGPUPrimitiveState{
			next_in_chain: unsafe { nil }
			topology: .wgpuprimitivetopology_trianglelist
			strip_index_format: .wgpuindexformat_undefined
			front_face: .wgpufrontface_ccw
			cull_mode: .wgpucullmode_none
		}
		depth_stencil: unsafe { nil }
		multisample: webgpu.WGPUMultisampleState{
			next_in_chain: unsafe { nil }
			count: 1
			mask: 0xffffffff
			alpha_to_coverage_enabled: 0
		}
		fragment: &fragment_state
	})

	bind_entries := [webgpu.WGPUBindGroupEntry{
		next_in_chain: unsafe { nil }
		binding: 0
		buffer: app.uniform_buffer
		offset: 0
		size: u64(sizeof(Uniforms))
		sampler: unsafe { nil }
		texture_view: unsafe { nil }
	}]
	app.bind_group = webgpu.wgpudevicecreatebindgroup(app.device, &webgpu.WGPUBindGroupDescriptor{
		next_in_chain: unsafe { nil }
		label: c'logo-bind-group'
		layout: app.bind_layout
		entry_count: bind_entries.len
		entries: bind_entries.data
	})

	app.resize_surface(win_w, win_h)
	app.upload_uniforms()
	webgpu.wgpuqueuewritebuffer(app.queue, app.vertex_buffer, 0, vertices.data, vertex_bytes)
}

fn (mut app App) upload_uniforms() {
	uniforms := Uniforms{
		angle: app.angle
		center: [2]f32{ f32(app.surface_width) * 0.5, f32(app.surface_height) * 0.5 }
		resolution: [2]f32{ f32(app.surface_width), f32(app.surface_height) }
		tint: [4]f32{ 1.0, 1.0, 1.0, 1.0 }
	}
	webgpu.wgpuqueuewritebuffer(app.queue, app.uniform_buffer, 0, &uniforms, sizeof(Uniforms))
}

fn build_logo_mesh() []Vertex {
	mut verts := []Vertex{cap: 256}
	shadow := Vec2{ x: 12, y: 12 }
	left_top := Vec2{ x: -168, y: -156 }
	joint := Vec2{ x: 0, y: 168 }
	right_top := Vec2{ x: 168, y: -156 }
	add_thick_segment(mut verts, left_top + shadow, joint + shadow, 36, Vertex{ r: 0.05, g: 0.08, b: 0.13, a: 1.0 })
	add_thick_segment(mut verts, joint + shadow, right_top + shadow, 36, Vertex{ r: 0.05, g: 0.08, b: 0.13, a: 1.0 })
	add_thick_segment(mut verts, left_top, joint, 36, Vertex{ r: 0.27, g: 0.55, b: 1.0, a: 1.0 })
	add_thick_segment(mut verts, joint, right_top, 36, Vertex{ r: 0.28, g: 0.78, b: 1.0, a: 1.0 })
	add_ring(mut verts, Vec2{ x: 0, y: 0 }, 208, 6, 80, Vertex{ r: 0.43, g: 0.53, b: 0.71, a: 1.0 })
	return verts
}

fn add_ring(mut verts []Vertex, center Vec2, radius f32, thickness f32, segments int, color Vertex) {
	for i in 0 .. segments {
		a0 := f32(i) / f32(segments) * math.pi * 2.0
		a1 := f32(i + 1) / f32(segments) * math.pi * 2.0
		p0 := Vec2{ x: center.x + math.cos(a0) * radius, y: center.y + math.sin(a0) * radius }
		p1 := Vec2{ x: center.x + math.cos(a1) * radius, y: center.y + math.sin(a1) * radius }
		add_thick_segment(mut verts, p0, p1, thickness, color)
	}
}

fn add_thick_segment(mut verts []Vertex, a Vec2, b Vec2, thickness f32, color Vertex) {
	dx := b.x - a.x
	dy := b.y - a.y
	len := math.sqrt(dx * dx + dy * dy)
	if len <= 0.0001 {
		return
	}
	half := thickness * 0.5
	nx := -dy / len * half
	ny := dx / len * half
	p0 := Vec2{ x: a.x + nx, y: a.y + ny }
	p1 := Vec2{ x: a.x - nx, y: a.y - ny }
	p2 := Vec2{ x: b.x - nx, y: b.y - ny }
	p3 := Vec2{ x: b.x + nx, y: b.y + ny }
	verts << Vertex{ x: p0.x, y: p0.y, r: color.r, g: color.g, b: color.b, a: color.a }
	verts << Vertex{ x: p1.x, y: p1.y, r: color.r, g: color.g, b: color.b, a: color.a }
	verts << Vertex{ x: p2.x, y: p2.y, r: color.r, g: color.g, b: color.b, a: color.a }
	verts << Vertex{ x: p0.x, y: p0.y, r: color.r, g: color.g, b: color.b, a: color.a }
	verts << Vertex{ x: p2.x, y: p2.y, r: color.r, g: color.g, b: color.b, a: color.a }
	verts << Vertex{ x: p3.x, y: p3.y, r: color.r, g: color.g, b: color.b, a: color.a }
}

fn (a Vec2) + (b Vec2) Vec2 {
	return Vec2{ x: a.x + b.x, y: a.y + b.y }
}
		p0 := Vec2{ x: center.x + math.cos(a0) * radius, y: center.y + math.sin(a0) * radius }
