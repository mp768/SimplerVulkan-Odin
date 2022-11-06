package SimplerVulkan

import vk "vendor:vulkan"
import "core:mem"
import "core:fmt"

// you can make this a uniform and avoid needing data and the size of it
Create_Buffer :: proc(device: Device, cmd_buffers: Command_Buffers, buffer_type: vk.BufferUsageFlag, data: rawptr, size_of_data: int) -> (buffer: Buffer) {
	buffer.size = vk.DeviceSize(size_of_data)
	buffer.mapped = true
	buffer.usage_type = buffer_type

	Create_VK_Buffer(device, buffer.size, { .UNIFORM_BUFFER if buffer_type == .UNIFORM_BUFFER else .TRANSFER_SRC, buffer_type  }, { .HOST_VISIBLE, .HOST_COHERENT }, &buffer.staging, &buffer.staging_mem)

	vk.MapMemory(device.logical_device, buffer.staging_mem, 0, buffer.size, {}, &buffer.data_mapping)
	Update_Buffer(device, cmd_buffers, buffer, data)

	if buffer_type != .UNIFORM_BUFFER && buffer_type != .TRANSFER_SRC {
		Create_VK_Buffer(device, buffer.size, { .TRANSFER_DST, buffer_type }, { .DEVICE_LOCAL }, &buffer.main, &buffer.main_mem)

		cmd_buffer := begin_temp_command_buffer(device, cmd_buffers)
		defer end_temp_command_buffer(device, cmd_buffers, &cmd_buffer)

		copy_region := vk.BufferCopy {
			size = buffer.size,
		}

		vk.CmdCopyBuffer(cmd_buffer, buffer.staging, buffer.main, 1, &copy_region)
	}

	return
}

/*

I should make a dynamically updating buffer, which will update it's size if it's too small to accomdate the new data size, 
but will zero out the memory if the new data is smaller than the previous data size.

Dynamic_Update_Buffer(device, cmd_buffers, &buffer, data, size_of_data, false) {
	// at the end of the function stores the previous_size into buffer

	if size_of_data > buffer.size do create_new_buffer()
	if size_of_data < buffer.previous_size do mem.zero()

	Update_Buffer(device, cmd_buffers, buffer, data, false)

	buffer.previous_size = size_of_data
}

something like this, it makes updating the buffer more efficient and use less computing resources since we won't need to recreate it too often.

*/

Dynamically_Update_Buffer :: proc(device: Device, cmd_buffers: Command_Buffers, buffer: ^Buffer, data: rawptr, data_size: int, update_main_mem := false) {
	if vk.DeviceSize(data_size) > buffer.size {
		type := buffer.usage_type
		Delete_Buffer(device, buffer)

		buffer^ = Create_Buffer(device, cmd_buffers, type, data, data_size)
		return 
	} 

	if vk.DeviceSize(data_size) < buffer.previous_size do mem.zero(buffer.data_mapping, int(buffer.previous_size))

	Update_Buffer(device, cmd_buffers, buffer^, data, update_main_mem)

	buffer.previous_size = vk.DeviceSize(data_size)
}

Update_Buffer :: proc(device: Device, cmd_buffers: Command_Buffers, buffer: Buffer, data: rawptr, update_main_mem := false) {
	if data != nil do mem.copy_non_overlapping(buffer.data_mapping, data, int(buffer.size))

	if update_main_mem && buffer.usage_type != .UNIFORM_BUFFER && buffer.usage_type != .TRANSFER_SRC {
		cmd_buffer := begin_temp_command_buffer(device, cmd_buffers)
		defer end_temp_command_buffer(device, cmd_buffers, &cmd_buffer)

		copy_region := vk.BufferCopy {
			size = buffer.size,
		}

		vk.CmdCopyBuffer(cmd_buffer, buffer.staging, buffer.main, 1, &copy_region)
	}
}

Unmap_Buffer_Memory :: #force_inline proc(device: Device, buffer: ^Buffer) {
	if !buffer.mapped do return

	vk.UnmapMemory(device.logical_device, buffer.staging_mem)
	buffer.mapped = false
}

Delete_Buffer :: proc(device: Device, buffer: ^Buffer) {
	Unmap_Buffer_Memory(device, buffer)

	vk.DestroyBuffer(device.logical_device, buffer.staging, nil)
	if buffer.usage_type != .UNIFORM_BUFFER && buffer.usage_type != .TRANSFER_SRC do vk.DestroyBuffer(device.logical_device, buffer.main, nil)

	vk.FreeMemory(device.logical_device, buffer.staging_mem, nil)
	if buffer.usage_type != .UNIFORM_BUFFER && buffer.usage_type != .TRANSFER_SRC do vk.FreeMemory(device.logical_device, buffer.main_mem, nil)
}