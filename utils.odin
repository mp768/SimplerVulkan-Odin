package SimplerVulkan

import vk "vendor:vulkan"

Find_Memory_Type :: proc(device: Device, type_filter: u32, propeties: vk.MemoryPropertyFlags) -> u32 {
	mem_properties: vk.PhysicalDeviceMemoryProperties 
	vk.GetPhysicalDeviceMemoryProperties(device.physical_device, &mem_properties)

	for i in 0..<mem_properties.memoryTypeCount {
		if bool(type_filter & u32(1 << i)) && mem_properties.memoryTypes[i].propertyFlags & propeties == propeties {
			return i
		}
	}

	Print_Error("failed to find suitable memory type")
	return 0
}

begin_temp_command_buffer :: proc(device: Device, cmd_buffers: Command_Buffers) -> (cmd_buffer: vk.CommandBuffer) {
	alloc_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		level              = .PRIMARY,
		commandPool        = cmd_buffers.pool,
		commandBufferCount = 1,
	}

	vk.AllocateCommandBuffers(device.logical_device, &alloc_info, &cmd_buffer)

	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = { .ONE_TIME_SUBMIT },
	}

	vk.BeginCommandBuffer(cmd_buffer, &begin_info)

	return
}

end_temp_command_buffer :: proc(device: Device, cmd_buffers: Command_Buffers, cmd_buffer: ^vk.CommandBuffer) {
	vk.EndCommandBuffer(cmd_buffer^)

	submit_info := vk.SubmitInfo {
		sType              = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers    = cmd_buffer,
	}

	vk.QueueSubmit(cmd_buffers.submit_queue, 1, &submit_info, {})
	vk.QueueWaitIdle(cmd_buffers.submit_queue)

	vk.FreeCommandBuffers(device.logical_device, cmd_buffers.pool, 1, cmd_buffer)
}

convert_source_to_shader_module :: proc(device: Device, source: []byte) -> (shader_module: vk.ShaderModule, ok: bool) {
	shader_module_info := vk.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(source),
		pCode    = cast(^u32)raw_data(source),
	}

	if vk.CreateShaderModule(device.logical_device, &shader_module_info, nil, &shader_module) != vk.Result.SUCCESS {
		Print_Error("failed to create a shader module!")
		return shader_module, false		
	}

	return shader_module, true
}

allocate_transition_image_layout :: #force_inline proc(device: Device, cmd_buffers: Command_Buffers, images: []vk.Image, transition_src, transition_dst: vk.ImageLayout) {
	cmd_buffer := begin_temp_command_buffer(device, cmd_buffers)
	defer end_temp_command_buffer(device, cmd_buffers, &cmd_buffer)

	transition_image_layout(cmd_buffer, images, transition_src, transition_dst)
}

transition_image_layout :: proc(cmd_buffer: vk.CommandBuffer, images: []vk.Image, transition_src, transition_dst: vk.ImageLayout) {
	barriers := make([]vk.ImageMemoryBarrier, len(images), context.temp_allocator)
	source_stage, destination_stage: vk.PipelineStageFlags

	for barrier, i in &barriers {
		barrier = vk.ImageMemoryBarrier {
			sType               = .IMAGE_MEMORY_BARRIER,
			oldLayout           = transition_src,
			newLayout           = transition_dst,
			srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			image               = images[i],

			subresourceRange = {
				aspectMask     = { .COLOR },
				baseMipLevel   = 0,
				levelCount     = 1,
				baseArrayLayer = 0,
				layerCount     = 1,
			},

			srcAccessMask       = {},
			dstAccessMask       = {},
		}

		#partial switch transition_src {
			case .UNDEFINED: 
				source_stage = { .TOP_OF_PIPE }

			case .TRANSFER_DST_OPTIMAL:
				barrier.srcAccessMask = { .TRANSFER_WRITE }
				source_stage          = { .TRANSFER }

			case .SHADER_READ_ONLY_OPTIMAL:
				barrier.srcAccessMask = { .SHADER_READ }
				source_stage          = { .FRAGMENT_SHADER }

			case .PRESENT_SRC_KHR:
				barrier.srcAccessMask = { .HOST_WRITE }
				source_stage          = { .HOST }

			case .SHARED_PRESENT_KHR:
				barrier.srcAccessMask = { .HOST_WRITE }
				source_stage          = { .HOST }

			case:
				Print_Error("unsupported layout transition (old): ", transition_src, "!")
				return  
		}

		#partial switch transition_dst {
			case .TRANSFER_DST_OPTIMAL:
				barrier.dstAccessMask = { .TRANSFER_WRITE }
				destination_stage     = { .TRANSFER }

			case .SHADER_READ_ONLY_OPTIMAL: 
				barrier.dstAccessMask = { .SHADER_READ }
				destination_stage     = { .FRAGMENT_SHADER }

			case .PRESENT_SRC_KHR:
				barrier.dstAccessMask = { .HOST_WRITE }
				destination_stage     = { .HOST }

			case .SHARED_PRESENT_KHR:
				barrier.dstAccessMask = { .HOST_WRITE }
				destination_stage     = { .HOST }

			case: 
				Print_Error("unsupported layout transition (new): ", transition_dst, "!")
				return
		}
	}

	vk.CmdPipelineBarrier(cmd_buffer, source_stage, destination_stage, {}, 0, nil, 0, nil, u32(len(barriers)), raw_data(barriers))
	return
}

Create_VK_Buffer :: proc(
	device: Device, 
	size: vk.DeviceSize, 
	usage: vk.BufferUsageFlags, 
	properties: vk.MemoryPropertyFlags, 
	buffer: ^vk.Buffer, 
	buffer_memory: ^vk.DeviceMemory) -> bool
{
	buffer_info := vk.BufferCreateInfo {
		sType       = .BUFFER_CREATE_INFO,
		size        = size,
		usage       = usage,
		sharingMode = .EXCLUSIVE,
	}

	if vk.CreateBuffer(device.logical_device, &buffer_info, nil, buffer) != vk.Result.SUCCESS {
		Print_Error("failed to create buffer")
		return false
	}

	mem_requirements: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(device.logical_device, buffer^, &mem_requirements)

	alloc_info := vk.MemoryAllocateInfo {
		sType = .MEMORY_ALLOCATE_INFO,
		allocationSize = mem_requirements.size,
		memoryTypeIndex = Find_Memory_Type(device, mem_requirements.memoryTypeBits, properties),
	}

	if vk.AllocateMemory(device.logical_device, &alloc_info, nil, buffer_memory) != vk.Result.SUCCESS {
		Print_Error("failed to allocate memory for buffer!")
		return false
	}

	vk.BindBufferMemory(device.logical_device, buffer^, buffer_memory^, 0)

	return true
}	

// allows me to transform the required features of the user from an array to a boolean, which is helpful for usability
Check_Physical_Device_Features :: proc(device: vk.PhysicalDevice, required_device_features: []Device_Feature) -> bool {
	device_supports_features := true

	device_features: vk.PhysicalDeviceFeatures
	vk.GetPhysicalDeviceFeatures(device, &device_features)

	for required_feature in required_device_features {
		switch required_feature {
			case .ALPHA_TO_ONE:
				device_supports_features &&= cast(bool)device_features.alphaToOne

			case .DEPTH_BIAS_CLAMP:
				device_supports_features &&= cast(bool)device_features.depthBiasClamp

			case .DEPTH_BOUNDS:
				device_supports_features &&= cast(bool)device_features.depthBounds

			case .DEPTH_CLAMP:
				device_supports_features &&= cast(bool)device_features.depthClamp

			case .DRAW_INDIRECT_FIRST_INSTANCE:
				device_supports_features &&= cast(bool)device_features.drawIndirectFirstInstance

			case .DUAL_SRC_BLEND:
				device_supports_features &&= cast(bool)device_features.dualSrcBlend

			case .FILL_MODE_NON_SOLID:
				device_supports_features &&= cast(bool)device_features.fillModeNonSolid

			case .FRAGMENT_STORES_AND_ATOMICS:
				device_supports_features &&= cast(bool)device_features.fragmentStoresAndAtomics

			case .FULL_DRAW_INDEX_UINT_32:
				device_supports_features &&= cast(bool)device_features.fullDrawIndexUint32

			case .GEOMETRY_SHADER:
				device_supports_features &&= cast(bool)device_features.geometryShader

			case .INDEPENDENT_BLEND:
				device_supports_features &&= cast(bool)device_features.independentBlend

			case .IMAGE_CUBE_ARRAY:
				device_supports_features &&= cast(bool)device_features.imageCubeArray

			case .INHERITED_QUERIES:
				device_supports_features &&= cast(bool)device_features.inheritedQueries

			case .LARGE_POINTS:
				device_supports_features &&= cast(bool)device_features.largePoints

			case .LOGIC_OP:
				device_supports_features &&= cast(bool)device_features.logicOp

			case .MULTI_DRAW_INDIRECT:
				device_supports_features &&= cast(bool)device_features.multiDrawIndirect

			case .MULTI_VIEWPORT:
				device_supports_features &&= cast(bool)device_features.multiViewport

			case .OCCLUSION_QUERY_PRECISE:
				device_supports_features &&= cast(bool)device_features.occlusionQueryPrecise

			case .PIPELINE_STATISTICS_QUERY:
				device_supports_features &&= cast(bool)device_features.pipelineStatisticsQuery

			case .ROBUST_BUFFER_ACCESS:
				device_supports_features &&= cast(bool)device_features.robustBufferAccess

			case .SAMPLER_ANISOTROPY:
				device_supports_features &&= cast(bool)device_features.samplerAnisotropy

			case .SAMPLE_RATE_SHADING:
				device_supports_features &&= cast(bool)device_features.sampleRateShading

			case .SHADER_CLIP_DISTANCE:
				device_supports_features &&= cast(bool)device_features.shaderClipDistance

			case .SHADER_CULL_DISTANCE:
				device_supports_features &&= cast(bool)device_features.shaderCullDistance

			case .SHADER_FLOAT_64:
				device_supports_features &&= cast(bool)device_features.shaderFloat64

			case .SHADER_IMAGE_GATHER_EXTENDED:
				device_supports_features &&= cast(bool)device_features.shaderImageGatherExtended

			case .SHADER_INT_16:
				device_supports_features &&= cast(bool)device_features.shaderInt16

			case .SHADER_INT_64:
				device_supports_features &&= cast(bool)device_features.shaderInt64

			case .SHADER_RESOURCE_MIN_LOD:
				device_supports_features &&= cast(bool)device_features.shaderResourceMinLod

			case .SHADER_RESOURCE_RESIDENCY:
				device_supports_features &&= cast(bool)device_features.shaderResourceResidency

			case .SHADER_SMAPLED_IMAGE_ARRAY_DYNAMIC_INDEXING:
				device_supports_features &&= cast(bool)device_features.shaderSampledImageArrayDynamicIndexing

			case .SHADER_STORAGE_BUFFER_ARRAY_DYNAMIC_INDEXING:
				device_supports_features &&= cast(bool)device_features.shaderStorageBufferArrayDynamicIndexing

			case .SHADER_STORAGE_IMAGE_ARRAY_DYNAMIC_INDEXING:
				device_supports_features &&= cast(bool)device_features.shaderStorageImageArrayDynamicIndexing

			case .SHADER_STORAGE_IMAGE_EXTENDED_FORMATS:
				device_supports_features &&= cast(bool)device_features.shaderStorageImageExtendedFormats

			case .SHADER_STORAGE_IMAGE_MULTISAMPLE:
				device_supports_features &&= cast(bool)device_features.shaderStorageImageMultisample

			case .SHADER_STORAGE_IMAGE_READ_WITHOUT_FORMAT:
				device_supports_features &&= cast(bool)device_features.shaderStorageImageReadWithoutFormat

			case .SHADER_STORAGE_IMAGE_WRITE_WITHOUT_FORMAT:
				device_supports_features &&= cast(bool)device_features.shaderStorageImageWriteWithoutFormat

			case .SHADER_TESSELLATION_AND_GEOMETRY_POINT_SIZE:
				device_supports_features &&= cast(bool)device_features.shaderTessellationAndGeometryPointSize

			case .SHADER_UNIFORM_BUFFER_ARRAY_DYNAMIC_INDEXING:
				device_supports_features &&= cast(bool)device_features.shaderUniformBufferArrayDynamicIndexing

			case .SPARSE_BINDING:
				device_supports_features &&= cast(bool)device_features.sparseBinding

			case .SPARSE_RESIDENCY_2_SAMPLES:
				device_supports_features &&= cast(bool)device_features.sparseResidency2Samples

			case .SPARSE_RESIDENCY_4_SAMPLES:
				device_supports_features &&= cast(bool)device_features.sparseResidency4Samples

			case .SPARSE_RESIDENCY_8_SAMPLES:
				device_supports_features &&= cast(bool)device_features.sparseResidency8Samples

			case .SPARSE_RESIDENCY_16_SAMPLES:
				device_supports_features &&= cast(bool)device_features.sparseResidency16Samples

			case .SPARSE_RESIDENCY_ALIASED:
				device_supports_features &&= cast(bool)device_features.sparseResidencyAliased

			case .SPARSE_RESIDENCY_BUFFER:
				device_supports_features &&= cast(bool)device_features.sparseResidencyBuffer

			case .SPARSE_RESIDENCY_IMAGE_2D:
				device_supports_features &&= cast(bool)device_features.sparseResidencyImage2D

			case .SPARSE_RESIDENCY_IMAGE_3D:
				device_supports_features &&= cast(bool)device_features.sparseResidencyImage3D

			case .TESSELLATION_SHADER:
				device_supports_features &&= cast(bool)device_features.tessellationShader

			case .TEXTURE_COMPRESSION_ASTC_LDR:
				device_supports_features &&= cast(bool)device_features.textureCompressionASTC_LDR

			case .TEXTURE_COMPRESSION_BC:
				device_supports_features &&= cast(bool)device_features.textureCompressionBC

			case .TEXTURE_COMPRESSION_ETC2:
				device_supports_features &&= cast(bool)device_features.textureCompressionETC2

			case .VARIABLE_MULTISAMPLE_RATE:
				device_supports_features &&= cast(bool)device_features.variableMultisampleRate

			case .VERTEX_PIPELINE_STORES_AND_ATOMICS:
				device_supports_features &&= cast(bool)device_features.vertexPipelineStoresAndAtomics

			case .WIDE_LINES:
				device_supports_features &&= cast(bool)device_features.wideLines
		}
	}

	return device_supports_features
}

// allows the user to create the physical device features to request the logical device to use easier.
Create_Physical_Device_Features :: proc(required_device_features: []Device_Feature) -> (device_features: vk.PhysicalDeviceFeatures) {
	for required_feature in required_device_features {
		switch required_feature {
			case .ALPHA_TO_ONE:
				device_features.alphaToOne = true

			case .DEPTH_BIAS_CLAMP:
				device_features.depthBiasClamp = true

			case .DEPTH_BOUNDS:
				device_features.depthBounds = true

			case .DEPTH_CLAMP:
				device_features.depthClamp = true

			case .DRAW_INDIRECT_FIRST_INSTANCE:
				device_features.drawIndirectFirstInstance = true

			case .DUAL_SRC_BLEND:
				device_features.dualSrcBlend = true

			case .FILL_MODE_NON_SOLID:
				device_features.fillModeNonSolid = true

			case .FRAGMENT_STORES_AND_ATOMICS:
				device_features.fragmentStoresAndAtomics = true

			case .FULL_DRAW_INDEX_UINT_32:
				device_features.fullDrawIndexUint32 = true

			case .GEOMETRY_SHADER:
				device_features.geometryShader = true

			case .INDEPENDENT_BLEND:
				device_features.independentBlend = true

			case .IMAGE_CUBE_ARRAY:
				device_features.imageCubeArray = true

			case .INHERITED_QUERIES:
				device_features.inheritedQueries = true

			case .LARGE_POINTS:
				device_features.largePoints = true

			case .LOGIC_OP:
				device_features.logicOp = true

			case .MULTI_DRAW_INDIRECT:
				device_features.multiDrawIndirect = true

			case .MULTI_VIEWPORT:
				device_features.multiViewport = true

			case .OCCLUSION_QUERY_PRECISE:
				device_features.occlusionQueryPrecise = true

			case .PIPELINE_STATISTICS_QUERY:
				device_features.pipelineStatisticsQuery = true

			case .ROBUST_BUFFER_ACCESS:
				device_features.robustBufferAccess = true

			case .SAMPLER_ANISOTROPY:
				device_features.samplerAnisotropy = true

			case .SAMPLE_RATE_SHADING:
				device_features.sampleRateShading = true

			case .SHADER_CLIP_DISTANCE:
				device_features.shaderClipDistance = true

			case .SHADER_CULL_DISTANCE:
				device_features.shaderCullDistance = true

			case .SHADER_FLOAT_64:
				device_features.shaderFloat64 = true

			case .SHADER_IMAGE_GATHER_EXTENDED:
				device_features.shaderImageGatherExtended = true

			case .SHADER_INT_16:
				device_features.shaderInt16 = true

			case .SHADER_INT_64:
				device_features.shaderInt64 = true

			case .SHADER_RESOURCE_MIN_LOD:
				device_features.shaderResourceMinLod = true

			case .SHADER_RESOURCE_RESIDENCY:
				device_features.shaderResourceResidency = true

			case .SHADER_SMAPLED_IMAGE_ARRAY_DYNAMIC_INDEXING:
				device_features.shaderSampledImageArrayDynamicIndexing = true

			case .SHADER_STORAGE_BUFFER_ARRAY_DYNAMIC_INDEXING:
				device_features.shaderStorageBufferArrayDynamicIndexing = true

			case .SHADER_STORAGE_IMAGE_ARRAY_DYNAMIC_INDEXING:
				device_features.shaderStorageImageArrayDynamicIndexing = true

			case .SHADER_STORAGE_IMAGE_EXTENDED_FORMATS:
				device_features.shaderStorageImageExtendedFormats = true

			case .SHADER_STORAGE_IMAGE_MULTISAMPLE:
				device_features.shaderStorageImageMultisample = true

			case .SHADER_STORAGE_IMAGE_READ_WITHOUT_FORMAT:
				device_features.shaderStorageImageReadWithoutFormat = true

			case .SHADER_STORAGE_IMAGE_WRITE_WITHOUT_FORMAT:
				device_features.shaderStorageImageWriteWithoutFormat = true

			case .SHADER_TESSELLATION_AND_GEOMETRY_POINT_SIZE:
				device_features.shaderTessellationAndGeometryPointSize = true

			case .SHADER_UNIFORM_BUFFER_ARRAY_DYNAMIC_INDEXING:
				device_features.shaderUniformBufferArrayDynamicIndexing = true

			case .SPARSE_BINDING:
				device_features.sparseBinding = true

			case .SPARSE_RESIDENCY_2_SAMPLES:
				device_features.sparseResidency2Samples = true

			case .SPARSE_RESIDENCY_4_SAMPLES:
				device_features.sparseResidency4Samples = true

			case .SPARSE_RESIDENCY_8_SAMPLES:
				device_features.sparseResidency8Samples = true

			case .SPARSE_RESIDENCY_16_SAMPLES:
				device_features.sparseResidency16Samples = true

			case .SPARSE_RESIDENCY_ALIASED:
				device_features.sparseResidencyAliased = true

			case .SPARSE_RESIDENCY_BUFFER:
				device_features.sparseResidencyBuffer = true

			case .SPARSE_RESIDENCY_IMAGE_2D:
				device_features.sparseResidencyImage2D = true

			case .SPARSE_RESIDENCY_IMAGE_3D:
				device_features.sparseResidencyImage3D = true

			case .TESSELLATION_SHADER:
				device_features.tessellationShader = true

			case .TEXTURE_COMPRESSION_ASTC_LDR:
				device_features.textureCompressionASTC_LDR = true

			case .TEXTURE_COMPRESSION_BC:
				device_features.textureCompressionBC = true

			case .TEXTURE_COMPRESSION_ETC2:
				device_features.textureCompressionETC2 = true

			case .VARIABLE_MULTISAMPLE_RATE:
				device_features.variableMultisampleRate = true

			case .VERTEX_PIPELINE_STORES_AND_ATOMICS:
				device_features.vertexPipelineStoresAndAtomics = true

			case .WIDE_LINES:
				device_features.wideLines = true
		}
	}

	return
}

create_image_view :: proc(device: Device, image: vk.Image, format: vk.Format) -> (view: vk.ImageView, ok: bool) {
	ok = true

	view_info := vk.ImageViewCreateInfo {
		sType    = .IMAGE_VIEW_CREATE_INFO,
		image    = image,
		viewType = .D2,
		format   = format,

		subresourceRange = {
			aspectMask     = { .COLOR },
			baseMipLevel   = 0,
			levelCount     = 1,
			baseArrayLayer = 0,
			layerCount     = 1,
		},
	}

	if vk.CreateImageView(device.logical_device, &view_info, nil, &view) != vk.Result.SUCCESS {
		Print_Error("failed to create image view!")
		ok = false
	}

	return
}