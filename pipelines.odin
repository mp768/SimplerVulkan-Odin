package SimplerVulkan

import vk "vendor:vulkan"
import "core:os"

Create_Compute_Pipeline :: proc(device: Device, descriptors: ^Descriptors, compute_shader: string) -> (pipeline: Pipeline) {
	shader_source, source_ok := os.read_entire_file(compute_shader, context.temp_allocator)

	if !source_ok do return

	shader_module, ok := convert_source_to_shader_module(device, shader_source)
	defer vk.DestroyShaderModule(device.logical_device, shader_module, nil)

	if !ok do return

	compute_shader_info := vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = { .COMPUTE },
		module = shader_module,
		pName  = "main",
	}

	pipeline_layout_create_info := vk.PipelineLayoutCreateInfo {
		sType          = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount = 1,
		pSetLayouts    = &descriptors.layout,
	}

	if vk.CreatePipelineLayout(device.logical_device, &pipeline_layout_create_info, nil, &pipeline.layout) != vk.Result.SUCCESS {
		Print_Error("failed to create pipeline layout!")
		return
	}

	compute_pipeline_create_info := vk.ComputePipelineCreateInfo {
		sType = .COMPUTE_PIPELINE_CREATE_INFO,
		stage = compute_shader_info,
		layout = pipeline.layout,
	}

	if vk.CreateComputePipelines(device.logical_device, {}, 1, &compute_pipeline_create_info, nil, &pipeline.internal) != vk.Result.SUCCESS {
		Print_Error("failed to create compute pipeline!")
	}

	return
}

Create_Graphics_Pipeline :: proc(device: Device, swapchain: Swapchain, desciptors: ^Descriptors, graphics_pipeline_info: Graphics_Pipeline_Create_Info) -> (pipeline: Pipeline) {
	shader_stages := make([dynamic]vk.PipelineShaderStageCreateInfo)
	defer delete(shader_stages)

	shader_modules := make([dynamic]vk.ShaderModule)
	defer {
		for s in shader_modules do vk.DestroyShaderModule(device.logical_device, s, nil)
		delete(shader_modules)
	}

	for vertex_path in graphics_pipeline_info.vertex_shaders {
		vertex_source, input_ok := os.read_entire_file(vertex_path, context.temp_allocator)

		if !input_ok do return

		shader_module, ok := convert_source_to_shader_module(device, vertex_source)

		if !ok do return

		append(&shader_modules, shader_module)

		append(&shader_stages, vk.PipelineShaderStageCreateInfo {
				sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
				stage  = { .VERTEX },
				module = shader_module,
				pName  = "main", // the entry point
			})
	}

	for fragment_path in graphics_pipeline_info.fragment_shaders {
		fragment_source, input_ok := os.read_entire_file(fragment_path, context.temp_allocator)

		if !input_ok do return

		shader_module, ok := convert_source_to_shader_module(device, fragment_source)

		if !ok do return

		append(&shader_modules, shader_module)

		append(&shader_stages, vk.PipelineShaderStageCreateInfo {
				sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
				stage  = { .FRAGMENT },
				module = shader_module,
				pName  = "main", // the entry point
			})
	}

	vertex_input_info := vk.PipelineVertexInputStateCreateInfo {
		sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexAttributeDescriptionCount = u32(len(graphics_pipeline_info.attribute_descriptions)),
		pVertexAttributeDescriptions    = raw_data(graphics_pipeline_info.attribute_descriptions),
		vertexBindingDescriptionCount   = u32(len(graphics_pipeline_info.binding_descriptions)),
		pVertexBindingDescriptions      = raw_data(graphics_pipeline_info.binding_descriptions),
	}

	input_assembly := vk.PipelineInputAssemblyStateCreateInfo {
		sType                  = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology               = .TRIANGLE_LIST, // I'm just going to assume you want triangles to be drawn, for now at least
		primitiveRestartEnable = false,
	}

	// just going to assume you want to render to the whole screen
	viewport := vk.Viewport {
		x        = 0,
		y        = 0,
		width    = f32(swapchain.image_extent.width),
		height   = f32(swapchain.image_extent.height),
		minDepth = 0,
		maxDepth = 1,
	}

	// going to assume you don't want to cut anything
	scissor := vk.Rect2D {
		offset = { 0, 0 },
		extent = swapchain.image_extent,
	}

	viewport_state := vk.PipelineViewportStateCreateInfo {
		sType = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		pViewports    = &viewport,
		scissorCount  = 1,
		pScissors     = &scissor,
	}

	rasterizer := vk.PipelineRasterizationStateCreateInfo {
		sType                   = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		polygonMode             = graphics_pipeline_info.polygon_mode,
		cullMode                = graphics_pipeline_info.cull_mode,
		frontFace               = graphics_pipeline_info.front_face,
		lineWidth               = 1,
		rasterizerDiscardEnable = false,
		depthClampEnable        = false,
		depthBiasEnable         = false,
	}

	multisampling := vk.PipelineMultisampleStateCreateInfo {
		sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		sampleShadingEnable  = false,
		rasterizationSamples = { ._1 },
	}

	// I'll just assume you want alpha values
	color_blend_attachment := vk.PipelineColorBlendAttachmentState {
		colorWriteMask      = { .R, .G, .B, .A },
		blendEnable         = true,

		srcColorBlendFactor = .SRC_ALPHA,
		dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
		colorBlendOp        = .ADD,

		srcAlphaBlendFactor = .ONE,
		dstAlphaBlendFactor = .ONE,
		alphaBlendOp        = .ADD,
	}

	color_blending := vk.PipelineColorBlendStateCreateInfo {
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		logicOpEnable   = false,
		logicOp         = .COPY,
		attachmentCount = 1,
		pAttachments    = &color_blend_attachment,
		blendConstants  = { 0, 0, 0, 0 },
	}

	pipeline_layout_create_info := vk.PipelineLayoutCreateInfo {
		sType          = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount = 1,
		pSetLayouts    = &desciptors.layout,
	}

	if vk.CreatePipelineLayout(device.logical_device, &pipeline_layout_create_info, nil, &pipeline.layout) != vk.Result.SUCCESS {
		Print_Error("failed to create pipeline layout!")
		return
	}

	pipeline_create_info := vk.GraphicsPipelineCreateInfo {
		sType = .GRAPHICS_PIPELINE_CREATE_INFO,
		stageCount          = u32(len(shader_stages)),
		pStages             = raw_data(shader_stages),
		pVertexInputState   = &vertex_input_info,
		pInputAssemblyState = &input_assembly,
		pViewportState      = &viewport_state,
		pRasterizationState = &rasterizer,
		pMultisampleState   = &multisampling,
		pColorBlendState    = &color_blending,

		layout              = pipeline.layout,
		renderPass          = swapchain.render_pass,
		subpass             = 0,
	}

	if vk.CreateGraphicsPipelines(device.logical_device, {}, 1, &pipeline_create_info, nil, &pipeline.internal) != vk.Result.SUCCESS {
		Print_Error("failed to create a graphics pipeline!")
	}

	return
}

Delete_Pipeline :: proc(device: Device, pipeline: Pipeline) {
	vk.DestroyPipelineLayout(device.logical_device, pipeline.layout, nil)
	vk.DestroyPipeline(device.logical_device, pipeline.internal, nil)
}