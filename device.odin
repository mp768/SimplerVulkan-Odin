package SimplerVulkan 

import vk "vendor:vulkan"
import sdl "vendor:sdl2"
import "core:fmt"
import "core:c"
import "core:runtime"
import "core:strings"

Print_Error :: proc(args: ..any, loc := #caller_location) {
	fmt.eprint(args={ loc.file_path, "(", loc.line, ":", loc.column, ")	" }, sep="")
	fmt.eprintln(args=args, sep="")
}

Create_Device :: proc($window_type: Window_System, window: rawptr, validation_layers_on: bool, device_info: Device_Create_Info) -> (device: Device) {
	Init_Vulkan(window_type, nil)
	device.validation_enabled = validation_layers_on
	device.supported_queues   = device_info.required_queues
	device.window = window

	// creating an instance and debug messenger
	{
		if validation_layers_on && !Check_Validation_Layer(device_info.validation_layers) {
			Print_Error("failed to find validation layers!")
			return
		}

		application_info := vk.ApplicationInfo {
			sType              = .APPLICATION_INFO,
			pApplicationName   = device_info.app_name,
			applicationVersion = device_info.app_version,
			pEngineName        = device_info.engine_name,
			engineVersion      = device_info.engine_version,
			apiVersion         = device_info.api_version,
		}

		when window_type == .SDL {
			extension_count: c.uint
			extension_count_ok := sdl.Vulkan_GetInstanceExtensions(cast(^sdl.Window)window, &extension_count, nil)

			extension_names := make([]cstring, extension_count + (1 if validation_layers_on else 0))
			defer delete(extension_names)

			extension_count_ok = sdl.Vulkan_GetInstanceExtensions(cast(^sdl.Window)window, &extension_count, raw_data(extension_names))

			if validation_layers_on {
				extension_names[len(extension_names)-1] = vk.EXT_DEBUG_UTILS_EXTENSION_NAME
			}
		} else {
			Print_Error("Unsupported windowing system! can't find extensions for ", window_type)
			return
		}

		if !extension_count_ok {
			Print_Error("failed find vulkan instance extensions")
			return
		}

		create_info := vk.InstanceCreateInfo {
			sType                   = .INSTANCE_CREATE_INFO,
			pApplicationInfo        = &application_info,
			enabledExtensionCount   = auto_cast len(extension_names),
			ppEnabledExtensionNames = raw_data(extension_names),
			enabledLayerCount       = 0,
		}

		// the info needed to create the debug messenger for the instance
		debug_messenger_create_info := vk.DebugUtilsMessengerCreateInfoEXT {
			sType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
			messageSeverity = { .WARNING, .ERROR, .VERBOSE },
			messageType     = { .GENERAL, .PERFORMANCE, .VALIDATION },

			pfnUserCallback = Debug_Callback,
		}

		validation_layers := make([]cstring, len(device_info.validation_layers), context.temp_allocator)

		// this info is only neccessary if we request validation
		if validation_layers_on {
			create_info.enabledLayerCount   = u32(len(validation_layers))

			// convert string names in validation layers to cstring names
			for layer, i in &validation_layers {
				layer = strings.clone_to_cstring(device_info.validation_layers[i], context.temp_allocator)
			}

			create_info.ppEnabledLayerNames = raw_data(validation_layers)

			create_info.pNext = &debug_messenger_create_info
		}

		if vk.CreateInstance(&create_info, nil, &device.instance) != .SUCCESS {
			Print_Error("failed to create instance!")
			return
		}

		Init_Vulkan(window_type, device.instance)

		// create the debug messenger itself now
		if validation_layers_on && 
		   vk.CreateDebugUtilsMessengerEXT(device.instance, &debug_messenger_create_info, nil, &device.debug_messenger) != .SUCCESS {
		   	Print_Error("failed to create a debug messenger!")
		   	return
		}
	}

	// create surface depending on windowing system
	if device_info.required_queues.present {
		when window_type == .SDL {
			if !sdl.Vulkan_CreateSurface(cast(^sdl.Window)window, device.instance, &device.surface) {
				Print_Error("failed to create a surface!")
				return
			}
		} else {
			Print_Error("Unsupported windowing system! couldn't create surface with ", window_type)
			return
		}
	}

	// checking and finding a suitable physical graphics system
	{
		device_count: u32
		vk.EnumeratePhysicalDevices(device.instance, &device_count, nil)

		if device_count == 0 {
			Print_Error("failed to find a device with vulkan support!")
			return
		}

		physical_devices := make([]vk.PhysicalDevice, device_count)
		defer delete(physical_devices)

		vk.EnumeratePhysicalDevices(device.instance, &device_count, raw_data(physical_devices))

		for physical_device in physical_devices {
			if Is_Physical_Device_Suitable(physical_device, device.surface, device_info.required_queues, device_info.device_extensions, device_info.required_device_features) {
				device.physical_device = physical_device
				break
			}
		}

		if device.physical_device == nil {
			Print_Error("couldn't find a suitable device!")
			return
		}
	}

	// finally creating a logical device from the physical device
	{
		indices := Find_Queue_Families(device.physical_device, device.surface, device_info.required_queues)

		unique_queue_families := make([dynamic]u32, context.temp_allocator)

		if device_info.required_queues.compute  do append(&unique_queue_families, indices.compute.?)
		if device_info.required_queues.graphics do append(&unique_queue_families, indices.graphics.?)
		if device_info.required_queues.present  do append(&unique_queue_families, indices.present.?)

		device_queue_create_infos := make([]vk.DeviceQueueCreateInfo, len(unique_queue_families), context.temp_allocator)

		queue_priority: f32 = 1

		for queue_family, i in unique_queue_families {
			device_queue_create_infos[i] = vk.DeviceQueueCreateInfo {
				sType            = .DEVICE_QUEUE_CREATE_INFO,
				queueFamilyIndex = queue_family,
				queueCount       = 1,
				pQueuePriorities = &queue_priority,
			}
		}

		device_features := Create_Physical_Device_Features(device_info.required_device_features)

		device_extensions := make([]cstring, len(device_info.device_extensions), context.temp_allocator)
		for s, i in &device_extensions do s = strings.clone_to_cstring(device_info.device_extensions[i], context.temp_allocator)

		logical_device_create_info := vk.DeviceCreateInfo {
			sType                   = .DEVICE_CREATE_INFO,
			queueCreateInfoCount    = u32(len(device_queue_create_infos)),
			pQueueCreateInfos       = raw_data(device_queue_create_infos),
			enabledExtensionCount   = u32(len(device_extensions)),
			ppEnabledExtensionNames = raw_data(device_extensions),
			enabledLayerCount       = 0,
			pEnabledFeatures        = &device_features,
		}

		validation_layers := make([]cstring, len(device_info.validation_layers), context.temp_allocator)
		for s, i in &validation_layers do s = strings.clone_to_cstring(device_info.validation_layers[i], context.temp_allocator)

		if validation_layers_on {
			logical_device_create_info.enabledLayerCount = u32(len(validation_layers))
			logical_device_create_info.ppEnabledLayerNames = raw_data(validation_layers)
		}

		if vk.CreateDevice(device.physical_device, &logical_device_create_info, nil, &device.logical_device) != vk.Result.SUCCESS {
			Print_Error("failed to create logical device!")
			return
		}

		if device_info.required_queues.compute  do vk.GetDeviceQueue(device.logical_device, indices.compute.?, 0, &device.compute_queue)
		if device_info.required_queues.graphics do vk.GetDeviceQueue(device.logical_device, indices.graphics.?, 0, &device.graphics_queue)
		if device_info.required_queues.present  do vk.GetDeviceQueue(device.logical_device, indices.present.?, 0, &device.present_queue)
	}

	return
}

Delete_Device :: proc(device: Device) {
	if device.validation_enabled {
		vk.DestroyDebugUtilsMessengerEXT(device.instance, device.debug_messenger, nil)
	}

	if device.supported_queues.present {
		vk.DestroySurfaceKHR(device.instance, device.surface, nil)
	}

	vk.DestroyDevice(device.logical_device, nil)
	vk.DestroyInstance(device.instance, nil)
}

Check_Validation_Layer :: proc(validation_layers: []string) -> bool {
	layer_count: u32

	vk.EnumerateInstanceLayerProperties(&layer_count, nil)

	avaliable_layers := make([]vk.LayerProperties, layer_count)
	defer delete(avaliable_layers)

	vk.EnumerateInstanceLayerProperties(&layer_count, raw_data(avaliable_layers))

	avaliable_layer_names := make([]string, layer_count)
	defer {
		for layer_name in avaliable_layer_names do delete(layer_name)

		delete(avaliable_layer_names)
	}
	
	for layer_property, i in &avaliable_layers {
		str_len := 0

		for _byte in layer_property.layerName {
			if _byte == 0 do break
			str_len += 1
		}

		avaliable_layer_names[i] = strings.clone_from_bytes(layer_property.layerName[0:str_len])
	}

	for validation_layer in validation_layers {
		layer_found := false

		for layer_name in avaliable_layer_names {
			if layer_name == validation_layer {
				layer_found = true
				break
			}
		}

		if !layer_found do return false
	}

	return true
}

Is_Physical_Device_Suitable :: proc(device: vk.PhysicalDevice, surface: vk.SurfaceKHR, required_queues: Required_Queues, device_extensions: []string, required_device_features: []Device_Feature) -> bool {
	indices := Find_Queue_Families(device, surface, required_queues)

	extensions_supported := Check_Physical_Device_Extension_Support(device, device_extensions)

	// if you need present support we will look for it, but if you don't it will default to being 'true'
	swapchain_acceptable := !required_queues.present

	if !swapchain_acceptable && extensions_supported {
		swapchain_details := Query_Swapchain_Details(device, surface)

		swapchain_acceptable = len(swapchain_details.formats) != 0 && len(swapchain_details.present_modes) != 0
	}

	device_supports_features := Check_Physical_Device_Features(device, required_device_features)

	return Queue_Is_Complete(indices, required_queues) && extensions_supported && swapchain_acceptable && device_supports_features
} 

Find_Queue_Families :: proc(device: vk.PhysicalDevice, surface: vk.SurfaceKHR, required_queues: Required_Queues) -> (indices: Queue_Family_Indices) {
	queue_family_count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, nil)

	queue_familes := make([]vk.QueueFamilyProperties, queue_family_count)
	defer delete(queue_familes)

	vk.GetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, raw_data(queue_familes))

	for queue_family, i in queue_familes {
		if .GRAPHICS in queue_family.queueFlags {
			indices.graphics = u32(i)
		}

		if .COMPUTE in queue_family.queueFlags {
			indices.compute = u32(i)
		}

		// you can't get present support without a surface, so if you don't want present support than you don't need a surface
		if required_queues.present {
			present_support: b32
			vk.GetPhysicalDeviceSurfaceSupportKHR(device, u32(i), surface, &present_support)
	
			if present_support do indices.present = u32(i)
		}

		if Queue_Is_Complete(indices, required_queues) do return
	}

	return
}

Check_Physical_Device_Extension_Support :: proc(device: vk.PhysicalDevice, device_extensions: []string) -> bool {
	extension_count: u32
	vk.EnumerateDeviceExtensionProperties(device, nil, &extension_count, nil)

	avaliable_extensions := make([]vk.ExtensionProperties, extension_count, context.temp_allocator)

	vk.EnumerateDeviceExtensionProperties(device, nil, &extension_count, raw_data(avaliable_extensions))

	// it's required to make this 'dynamic' just because we need to be able to remove elements later on
	required_extensions := make([dynamic]string, 0, context.temp_allocator)

	for i in 0..<len(device_extensions) {
		append(&required_extensions, strings.clone(device_extensions[i], context.temp_allocator))
	}

	for extension in &avaliable_extensions {
		str_len := 0

		for _byte in extension.extensionName {
			if _byte == 0 do break
			str_len += 1
		}

		temp_extension_str := strings.clone_from_bytes(extension.extensionName[:str_len])
		defer delete(temp_extension_str)

		for required_extension, i in required_extensions {
			if temp_extension_str == required_extension {
				unordered_remove(&required_extensions, i)
			}
		}
	}

	return len(required_extensions) == 0
}

Query_Swapchain_Details :: proc(device: vk.PhysicalDevice, surface: vk.SurfaceKHR) -> (result: Swapchain_Details) {
	result = Swapchain_Details {
		capabilities  = {},
		formats       = make([dynamic]vk.SurfaceFormatKHR, context.temp_allocator),
		present_modes = make([dynamic]vk.PresentModeKHR, context.temp_allocator),
	}

	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface, &result.capabilities)

	format_count: u32
	vk.GetPhysicalDeviceSurfaceFormatsKHR(device, surface, &format_count, nil)

	if format_count != 0 {
		resize(&result.formats, int(format_count))

		vk.GetPhysicalDeviceSurfaceFormatsKHR(device, surface, &format_count, raw_data(result.formats))
	}

	present_count: u32
	vk.GetPhysicalDeviceSurfacePresentModesKHR(device, surface, &present_count, nil)

	if present_count != 0 {
		resize(&result.present_modes, int(present_count))

		vk.GetPhysicalDeviceSurfacePresentModesKHR(device, surface, &present_count, raw_data(result.present_modes))
	}

	return
}

Queue_Is_Complete :: proc(indices: Queue_Family_Indices, required_queues: Required_Queues) -> (result: bool) {
	_, graphics_ok := indices.graphics.?
	_, present_ok  := indices.present.?
	_, compute_ok  := indices.compute.?

	result = true

	if required_queues.graphics {
		result &&= graphics_ok
	}

	if required_queues.present {
		result &&= present_ok
	}

	if required_queues.compute {
		result &&= compute_ok
	}


	return
}

Debug_Callback :: proc "system"(
	message_severity: vk.DebugUtilsMessageSeverityFlagsEXT, 
	message_type: vk.DebugUtilsMessageTypeFlagsEXT, 
	callback_data: ^vk.DebugUtilsMessengerCallbackDataEXT, 
	user_data: rawptr) -> b32 {
	context = runtime.default_context()

	if (vk.DebugUtilsMessageSeverityFlagsEXT {.WARNING, .ERROR} >= message_severity) {
		fmt.eprintln(message_severity & {.ERROR, .WARNING}, "Layer:", callback_data.pMessage, "\n")
	}

	return false
}