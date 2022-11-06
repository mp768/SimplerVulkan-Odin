package SimplerVulkan

import vk "vendor:vulkan"

Create_Command_Buffers :: proc(device: Device, set_size: int, work_load: Desired_Workload) -> (cmd_buffers: Command_Buffers) {
	if set_size < 1 {
		Print_Error("hold on a minute, why are you trying to allocate command buffers with a size of ", set_size, " that's really stupid lol")
		return
	}

	// allocate command pool	
	{
		indices := Find_Queue_Families(device.physical_device, device.surface, device.supported_queues)

		pool_info := vk.CommandPoolCreateInfo {
			sType            = .COMMAND_POOL_CREATE_INFO,
			queueFamilyIndex = indices.graphics.? if work_load == .GRAPHICS else indices.compute.?,
			flags            = { .RESET_COMMAND_BUFFER },
		}

		cmd_buffers.submit_queue = device.graphics_queue if work_load == .GRAPHICS else device.compute_queue

		if vk.CreateCommandPool(device.logical_device, &pool_info, nil, &cmd_buffers.pool) != vk.Result.SUCCESS {
			Print_Error("failed to create a command pool for the command buffers!")
			return
		}
	}

	// allocate the command buffers
	{
		alloc_info := vk.CommandBufferAllocateInfo {
			sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
			commandPool        = cmd_buffers.pool,
			level              = .PRIMARY,
			commandBufferCount = u32(set_size),
		}

		cmd_buffers.buffers = make([]vk.CommandBuffer, set_size)

		if vk.AllocateCommandBuffers(device.logical_device, &alloc_info, raw_data(cmd_buffers.buffers)) != vk.Result.SUCCESS {
			Print_Error("failed to allocate the command buffers")
			return
		}
	}

	return
}

Delete_Command_Buffers :: proc(device: Device, command_buffers: Command_Buffers) {
	vk.FreeCommandBuffers(device.logical_device, command_buffers.pool, u32(len(command_buffers.buffers)), raw_data(command_buffers.buffers))
	vk.DestroyCommandPool(device.logical_device, command_buffers.pool, nil)

	delete(command_buffers.buffers)
}