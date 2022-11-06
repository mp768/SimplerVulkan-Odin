package SimplerVulkan

import vk "vendor:vulkan"
import sdl "vendor:sdl2"

Init_Vulkan :: #force_inline proc($window_type: Window_System, instance: Maybe(vk.Instance)) {
	Load_Data :: struct {
		instance: Maybe(vk.Instance),
		window_type: Window_System,
	}

	data := Load_Data {
		instance,
		window_type,
	}

	context.user_ptr = &data

	vk.load_proc_addresses(proc(p: rawptr, name: cstring) {
			data := cast(^Load_Data)context.user_ptr

			fptr: vk.ProcGetInstanceProcAddr

			switch data.window_type {
				case .SDL:
					fptr = auto_cast sdl.Vulkan_GetVkGetInstanceProcAddr()

				case .GLFW:
					// no implementation yet

				case .NONE:
					// have not implemented targets yet that use their own windowing system
			}

			instance, ok := data.instance.?

			(cast(^rawptr)p)^ = cast(rawptr)fptr(instance if ok else nil, name)
		})
}