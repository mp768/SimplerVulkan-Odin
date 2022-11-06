package SimplerVulkan

import vk "vendor:vulkan"

Create_Texture :: proc(device: Device, swapchain: Maybe(Swapchain), cmd_buffers: Command_Buffers, sample: bool, pixels: []byte, width, height, channels: int) -> (texture: Texture) {
	texture.width = auto_cast width
	texture.height = auto_cast height

	// set up the image
	{
		texture.sampled = sample
		texture.buffer = Create_Buffer(device, cmd_buffers, .TRANSFER_SRC, raw_data(pixels), width * height * channels)

		{
			image_info := vk.ImageCreateInfo {
				sType     = .IMAGE_CREATE_INFO,
				imageType = .D2,

				extent = {
					width  = u32(width),
					height = u32(height),
					depth  = 1,
				},

				mipLevels     = 1,
				arrayLayers   = 1,
				format        = .R8G8B8A8_SRGB if swapchain == nil else swapchain.?.image_format,
				tiling        = .OPTIMAL,
				initialLayout = .UNDEFINED,
				usage         = { .TRANSFER_DST, .SAMPLED if sample else .STORAGE, .COLOR_ATTACHMENT },
				sharingMode   = .EXCLUSIVE,
				samples       = { ._1 },
			}

			if vk.CreateImage(device.logical_device, &image_info, nil, &texture.image) != vk.Result.SUCCESS {
				Print_Error("failed to create image for texture!")
				return
			}

			mem_requirements: vk.MemoryRequirements
			vk.GetImageMemoryRequirements(device.logical_device, texture.image, &mem_requirements)

			alloc_info := vk.MemoryAllocateInfo {
				sType           = .MEMORY_ALLOCATE_INFO,
				allocationSize  = mem_requirements.size,
				memoryTypeIndex = Find_Memory_Type(device, mem_requirements.memoryTypeBits, { .DEVICE_LOCAL }),
			}

			if vk.AllocateMemory(device.logical_device, &alloc_info, nil, &texture.memory) != vk.Result.SUCCESS {
				Print_Error("Failed to allocate memory for image!")
				return
			}

			vk.BindImageMemory(device.logical_device, texture.image, texture.memory, 0)
		}

		allocate_transition_image_layout(device, cmd_buffers, []vk.Image { texture.image }, .UNDEFINED, .TRANSFER_DST_OPTIMAL)
		texture.image_layout = .TRANSFER_DST_OPTIMAL

		{
			cmd_buffer := begin_temp_command_buffer(device, cmd_buffers)
			defer end_temp_command_buffer(device, cmd_buffers, &cmd_buffer)

			region := vk.BufferImageCopy {
				bufferOffset      = 0,
				bufferRowLength   = 0,
				bufferImageHeight = 0,

				imageSubresource = {
					aspectMask     = { .COLOR },
					mipLevel       = 0,
					baseArrayLayer = 0,
					layerCount     = 1,
				},

				imageOffset = { 0, 0, 0 },
				imageExtent = {
					width  = u32(width),
					height = u32(height),
					depth  = 1,
				},
			}

			vk.CmdCopyBufferToImage(cmd_buffer, texture.buffer.staging, texture.image, .TRANSFER_DST_OPTIMAL, 1, &region)
		}

		if sample {
			allocate_transition_image_layout(device, cmd_buffers, []vk.Image { texture.image }, .TRANSFER_DST_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL)
			texture.image_layout = .SHADER_READ_ONLY_OPTIMAL
		}
	}

	// set up the image view
	{
		view, ok := create_image_view(device, texture.image, .R8G8B8A8_SRGB if swapchain == nil else swapchain.?.image_format) 

		if !ok do return

		texture.view = view
	}

	// set up sampler
	if sample {
		properties: vk.PhysicalDeviceProperties
		vk.GetPhysicalDeviceProperties(device.physical_device, &properties)

		sampler_info := vk.SamplerCreateInfo {
			sType                   = .SAMPLER_CREATE_INFO,
			magFilter               = .NEAREST,
			minFilter               = .NEAREST,

			addressModeU            = .REPEAT,
			addressModeV            = .REPEAT,
			addressModeW            = .REPEAT,

			anisotropyEnable        = false,
			maxAnisotropy           = properties.limits.maxSamplerAnisotropy,
			borderColor             = .INT_OPAQUE_BLACK,

			unnormalizedCoordinates = false,
			compareEnable           = false,
			compareOp               = .ALWAYS,

			mipmapMode              = .NEAREST,
			mipLodBias              = 0,
			minLod                  = 0,
			maxLod                  = 0,
		}

		if vk.CreateSampler(device.logical_device, &sampler_info, nil, &texture.sampler) != vk.Result.SUCCESS {
			Print_Error("failed to create texture sampler!")
			return
		}
	}

	if swapchain != nil {
		frame_buffer_info := vk.FramebufferCreateInfo {
			sType = .FRAMEBUFFER_CREATE_INFO,
			renderPass      = swapchain.?.render_pass,
			attachmentCount = 1,
			pAttachments    = &texture.view,
			width           = u32(texture.width),
			height          = u32(texture.height),
			layers          = 1,
		}

		if vk.CreateFramebuffer(device.logical_device, &frame_buffer_info, nil, &texture.frame_buffer) != vk.Result.SUCCESS {
			Print_Error("failed to create texture frame buffer!")
			return
		}		
	}

	return
}

Enable_Write_Texture :: #force_inline proc(device: Device, cmd_buffers: Command_Buffers, texture: ^Texture) {
	if texture.image_layout != .TRANSFER_DST_OPTIMAL do allocate_transition_image_layout(device, cmd_buffers, []vk.Image { texture.image }, texture.image_layout, .TRANSFER_DST_OPTIMAL)
	texture.image_layout = .TRANSFER_DST_OPTIMAL
}

Enable_Read_Texture :: #force_inline proc(device: Device, cmd_buffers: Command_Buffers, texture: ^Texture) {
	if texture.image_layout != .SHADER_READ_ONLY_OPTIMAL do allocate_transition_image_layout(device, cmd_buffers, []vk.Image { texture.image }, texture.image_layout, .SHADER_READ_ONLY_OPTIMAL)
	texture.image_layout = .SHADER_READ_ONLY_OPTIMAL
}

Update_Texture :: proc(device: Device, cmd_buffers: Command_Buffers, texture: ^Texture, pixels: []byte) {
	Update_Buffer(device, cmd_buffers, texture.buffer, raw_data(pixels))

	previous_layout := texture.image_layout

	if previous_layout != .TRANSFER_DST_OPTIMAL do allocate_transition_image_layout(device, cmd_buffers, []vk.Image { texture.image }, previous_layout, .TRANSFER_DST_OPTIMAL)

	{
		cmd_buffer := begin_temp_command_buffer(device, cmd_buffers)
		defer end_temp_command_buffer(device, cmd_buffers, &cmd_buffer)

		region := vk.BufferImageCopy {
			bufferOffset      = 0,
			bufferRowLength   = 0,
			bufferImageHeight = 0,

			imageSubresource = {
				aspectMask     = { .COLOR },
				mipLevel       = 0,
				baseArrayLayer = 0,
				layerCount     = 1,
			},

			imageOffset = { 0, 0, 0 },
			imageExtent = {
				width  = texture.width,
				height = texture.height,
				depth  = 1,
			},
		}

		vk.CmdCopyBufferToImage(cmd_buffer, texture.buffer.staging, texture.image, .TRANSFER_DST_OPTIMAL, 1, &region)
	}

	
	if previous_layout != .TRANSFER_DST_OPTIMAL do allocate_transition_image_layout(device, cmd_buffers, []vk.Image { texture.image }, .TRANSFER_DST_OPTIMAL, previous_layout)
}

import "core:fmt"

Delete_Texture :: proc(device: Device, texture: ^Texture) {
	vk.FreeMemory(device.logical_device, texture.memory, nil)
	vk.DestroyImage(device.logical_device, texture.image, nil)
	vk.DestroyImageView(device.logical_device, texture.view, nil)
	vk.DestroySampler(device.logical_device, texture.sampler, nil)

	if texture.frame_buffer != {} do vk.DestroyFramebuffer(device.logical_device, texture.frame_buffer, nil)

	Delete_Buffer(device, &texture.buffer)
}