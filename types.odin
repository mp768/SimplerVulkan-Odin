package SimplerVulkan

import vk "vendor:vulkan"

Device :: struct {
	instance: vk.Instance,
	debug_messenger: vk.DebugUtilsMessengerEXT,
	physical_device: vk.PhysicalDevice,
	logical_device: vk.Device,

	surface: vk.SurfaceKHR,

	graphics_queue, compute_queue, present_queue, tranfer_queue: vk.Queue,

	window_type: Window_System,

	window: rawptr,

	validation_enabled: bool,
	supported_queues: Required_Queues,
}

Swapchain :: struct {
	internal: vk.SwapchainKHR,
	render_pass: vk.RenderPass,
	images: []vk.Image,
	image_views: []vk.ImageView,
	image_format: vk.Format,
	image_extent: vk.Extent2D,
	frame_buffers: []vk.Framebuffer,
}

Descriptors :: struct {
	layout: vk.DescriptorSetLayout,
	pool: vk.DescriptorPool,
	sets: []vk.DescriptorSet,
}

Buffer :: struct {
	staging, main: vk.Buffer,
	staging_mem, main_mem: vk.DeviceMemory,
	previous_size, size: vk.DeviceSize,
	data_mapping: rawptr,
	usage_type: vk.BufferUsageFlag,

	mapped: bool,
}

Command_Buffers :: struct {
	pool: vk.CommandPool,
	buffers: []vk.CommandBuffer,
	submit_queue: vk.Queue,
}

Pipeline :: struct {
	internal: vk.Pipeline,
	layout: vk.PipelineLayout,
}

Graphics_Pipeline_Create_Info :: struct {
	vertex_shaders: []string,
	fragment_shaders: []string,

	binding_descriptions: []vk.VertexInputBindingDescription,
	attribute_descriptions: []vk.VertexInputAttributeDescription,

	polygon_mode: vk.PolygonMode,
	cull_mode: vk.CullModeFlags,
	front_face: vk.FrontFace,
}

Texture :: struct {
	image: vk.Image,
	view: vk.ImageView,
	memory: vk.DeviceMemory,

	sampler: vk.Sampler,
	frame_buffer: vk.Framebuffer,

	sampled: bool,

	width, height: u32,
	buffer: Buffer,
	image_layout: vk.ImageLayout,
}

Desired_Workload :: enum {
	GRAPHICS,
	COMPUTE,
}

Descriptor_Binding_Layout :: struct {
	descriptor_type: vk.DescriptorType,
	flags: vk.ShaderStageFlags,
}

Swapchain_Create_Info :: struct {
	color_space:  vk.ColorSpaceKHR,
	format:       vk.Format,
	present_mode: vk.PresentModeKHR,
}

Device_Create_Info :: struct {
	app_name: cstring,
	app_version: u32,
	engine_name: cstring, 
	engine_version: u32,

	api_version: u32,
	validation_layers: []string,
	device_extensions: []string,

	required_queues: Required_Queues,
	required_device_features: []Device_Feature,
}

Required_Queues :: struct {
	compute:  bool,
	present:  bool,
	graphics: bool,
}

Queue_Family_Indices :: struct {
	graphics, present, compute: Maybe(u32),
}

Swapchain_Details :: struct {
	capabilities:  vk.SurfaceCapabilitiesKHR,
	formats:       [dynamic]vk.SurfaceFormatKHR,
	present_modes: [dynamic]vk.PresentModeKHR,
}

Device_Feature :: enum {
	ROBUST_BUFFER_ACCESS, 
	FULL_DRAW_INDEX_UINT_32,                    
	IMAGE_CUBE_ARRAY,                            
	INDEPENDENT_BLEND,                         
	GEOMETRY_SHADER,   
	TESSELLATION_SHADER,                       
	SAMPLE_RATE_SHADING,                      
	DUAL_SRC_BLEND,                             
	LOGIC_OP,                                   
	MULTI_DRAW_INDIRECT,                         
	DRAW_INDIRECT_FIRST_INSTANCE,                 
	DEPTH_CLAMP,                                
	DEPTH_BIAS_CLAMP,                            
	FILL_MODE_NON_SOLID,                          
	DEPTH_BOUNDS,                               
	WIDE_LINES,                                 
	LARGE_POINTS,                               
	ALPHA_TO_ONE,                                
	MULTI_VIEWPORT,                             
	SAMPLER_ANISOTROPY,                         
	TEXTURE_COMPRESSION_ETC2,                    
	TEXTURE_COMPRESSION_ASTC_LDR,                
	TEXTURE_COMPRESSION_BC,                      
	OCCLUSION_QUERY_PRECISE,                    
	PIPELINE_STATISTICS_QUERY,                   
	VERTEX_PIPELINE_STORES_AND_ATOMICS,            
	FRAGMENT_STORES_AND_ATOMICS,                  
	SHADER_TESSELLATION_AND_GEOMETRY_POINT_SIZE,
	SHADER_IMAGE_GATHER_EXTENDED,                 
	SHADER_STORAGE_IMAGE_EXTENDED_FORMATS,         
	SHADER_STORAGE_IMAGE_MULTISAMPLE,             
	SHADER_STORAGE_IMAGE_READ_WITHOUT_FORMAT,       
	SHADER_STORAGE_IMAGE_WRITE_WITHOUT_FORMAT,      
	SHADER_UNIFORM_BUFFER_ARRAY_DYNAMIC_INDEXING,   
	SHADER_SMAPLED_IMAGE_ARRAY_DYNAMIC_INDEXING,   
	SHADER_STORAGE_BUFFER_ARRAY_DYNAMIC_INDEXING,   
	SHADER_STORAGE_IMAGE_ARRAY_DYNAMIC_INDEXING,    
	SHADER_CLIP_DISTANCE,                        
	SHADER_CULL_DISTANCE,                        
	SHADER_FLOAT_64,                             
	SHADER_INT_64,                               
	SHADER_INT_16,                               
	SHADER_RESOURCE_RESIDENCY,                   
	SHADER_RESOURCE_MIN_LOD,                      
	SPARSE_BINDING,                             
	SPARSE_RESIDENCY_BUFFER,                     
	SPARSE_RESIDENCY_IMAGE_2D,                  
	SPARSE_RESIDENCY_IMAGE_3D,                    
	SPARSE_RESIDENCY_2_SAMPLES,                   
	SPARSE_RESIDENCY_4_SAMPLES,                   
	SPARSE_RESIDENCY_8_SAMPLES,                   
	SPARSE_RESIDENCY_16_SAMPLES,                  
	SPARSE_RESIDENCY_ALIASED,                   
	VARIABLE_MULTISAMPLE_RATE,                  
	INHERITED_QUERIES,                          
}

Window_System :: enum {
	SDL,
	GLFW,
	NONE,
}

