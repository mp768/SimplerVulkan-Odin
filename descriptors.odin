package SimplerVulkan

import vk "vendor:vulkan"

Create_Descriptors :: proc(device: Device, set_size: int, binding_infos: []Descriptor_Binding_Layout) -> (descriptor: Descriptors) {
	// set up layout
	{
		bindings := make([dynamic]vk.DescriptorSetLayoutBinding, context.temp_allocator)

		for binding_info, i in binding_infos {
			append(&bindings, vk.DescriptorSetLayoutBinding {
				binding            = u32(i),
				descriptorCount    = 1,
				descriptorType     = binding_info.descriptor_type,
				pImmutableSamplers = nil,
				stageFlags         = binding_info.flags, 
			})
		}

		layout_info := vk.DescriptorSetLayoutCreateInfo {
			sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
			bindingCount = u32(len(bindings)),
			pBindings    = raw_data(bindings),
		}

		if vk.CreateDescriptorSetLayout(device.logical_device, &layout_info, nil, &descriptor.layout) != vk.Result.SUCCESS {
			Print_Error("failed to create descriptor layout!")
			return
		}
	}

	// create descriptor pool
	{
		pool_size := make([dynamic]vk.DescriptorPoolSize, context.temp_allocator)

		for binding_info in binding_infos {
			append(&pool_size, vk.DescriptorPoolSize {
					type            = binding_info.descriptor_type,
					descriptorCount = u32(set_size),
				})
		}

		pool_info := vk.DescriptorPoolCreateInfo {
			sType         = .DESCRIPTOR_POOL_CREATE_INFO,
			poolSizeCount = u32(len(pool_size)),
			pPoolSizes    = raw_data(pool_size),
			maxSets       = u32(set_size),
		}

		if vk.CreateDescriptorPool(device.logical_device, &pool_info, nil, &descriptor.pool) != vk.Result.SUCCESS {
			Print_Error("failed to create a descriptor pool!")
			return
		}
	}

	// create descriptor sets 
	{
		layouts := make([]vk.DescriptorSetLayout, set_size, context.temp_allocator)
		descriptor.sets = make([]vk.DescriptorSet, set_size)

		for layout in &layouts do layout = descriptor.layout

		alloc_info := vk.DescriptorSetAllocateInfo {
			sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
			descriptorPool     = descriptor.pool,
			descriptorSetCount = u32(len(layouts)),
			pSetLayouts        = raw_data(layouts),
		}

		if vk.AllocateDescriptorSets(device.logical_device, &alloc_info, raw_data(descriptor.sets)) != vk.Result.SUCCESS {
			Print_Error("failed to allocate descriptor sets!")
			return
		}
	}

	return
}

// update buffer to custom buffer later on
Write_Buffer_to_Descriptors :: proc(device: Device, descriptor: Descriptors, idx, dst_binding: int, type: vk.DescriptorType, buffer: Buffer) {
	buffer_info := vk.DescriptorBufferInfo {
		buffer = buffer.staging,
		offset = 0,
		range = buffer.size,
	}

	descriptor_write := vk.WriteDescriptorSet {
		sType           = .WRITE_DESCRIPTOR_SET,
		dstSet          = descriptor.sets[idx],
		dstBinding      = u32(dst_binding),
		dstArrayElement = 0,
		descriptorType  = type,
		descriptorCount = 1,
		pBufferInfo     = &buffer_info,
	}

	vk.UpdateDescriptorSets(device.logical_device, 1, &descriptor_write, 0, nil)
}

Write_Texture_to_Descriptors :: proc(device: Device, descriptor: Descriptors, idx, dst_binding: int, texture: Texture, sample: bool) {
	image_info := vk.DescriptorImageInfo {
		imageLayout = texture.image_layout,
		imageView   = texture.view,
	}

	if sample do image_info.sampler = texture.sampler

	descriptor_write := vk.WriteDescriptorSet {
		sType           = .WRITE_DESCRIPTOR_SET,
		dstSet          = descriptor.sets[idx],
		dstBinding      = u32(dst_binding),
		dstArrayElement = 0,
		descriptorType  = .COMBINED_IMAGE_SAMPLER if sample else .STORAGE_IMAGE,
		descriptorCount = 1,
		pImageInfo      = &image_info,
	}

	vk.UpdateDescriptorSets(device.logical_device, 1, &descriptor_write, 0, nil)
}

Delete_Descriptors :: proc(device: Device, descriptors: Descriptors) {
	vk.FreeDescriptorSets(device.logical_device, descriptors.pool, u32(len(descriptors.sets)), raw_data(descriptors.sets))
	vk.DestroyDescriptorPool(device.logical_device, descriptors.pool, nil)
	vk.DestroyDescriptorSetLayout(device.logical_device, descriptors.layout, nil)

	delete(descriptors.sets)
}