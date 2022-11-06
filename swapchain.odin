package SimplerVulkan

import vk "vendor:vulkan"
import sdl "vendor:sdl2"
import "core:c"
import "core:fmt"

// a swapchain needs a graphics queue and present queue, so we require it to create a swapchain successfully
Create_Swapchain :: proc(device: Device, swapchain_info: Swapchain_Create_Info) -> (swapchain: Swapchain) {
	if !device.supported_queues.present || !device.supported_queues.graphics {
		Print_Error("failed to create swapchain due to there being no present or graphics queue supported")
		return
	} 

	// set up swapchain
	{
		choose_swap_surface_format :: #force_inline proc(formats: []vk.SurfaceFormatKHR, color_space: vk.ColorSpaceKHR, format: vk.Format) -> vk.SurfaceFormatKHR {
			for avaliable_format in formats {
				if avaliable_format.colorSpace == color_space && avaliable_format.format == format {
					return avaliable_format
				}
			}

			// default to the first if we don't find the desired config
			return formats[0]
		}

		choose_swap_present_mode :: #force_inline proc(present_modes: []vk.PresentModeKHR, desired_present_mode: vk.PresentModeKHR) -> vk.PresentModeKHR {
			for present_mode in present_modes {
				if present_mode == desired_present_mode {
					return present_mode
				}
			}

			return .FIFO
		}

		choose_swap_extent :: #force_inline proc(capabilites: vk.SurfaceCapabilitiesKHR, window: rawptr, window_type: Window_System) -> (actual_extent: vk.Extent2D) {
			if capabilites.currentExtent.width != max(u32) {
				return capabilites.currentExtent
			}

			width, height: c.int

			if window_type == .SDL {
				sdl.GetWindowSize(cast(^sdl.Window)window, &width, &height)
			} else {
				Print_Error("Getting window size is not supported with ", window_type)
				return capabilites.currentExtent
			}

			actual_extent.width = clamp(u32(width), capabilites.minImageExtent.width, capabilites.maxImageExtent.width)
			actual_extent.height = clamp(u32(height), capabilites.minImageExtent.height, capabilites.maxImageExtent.height)

			return
		}

		swapchain_support := Query_Swapchain_Details(device.physical_device, device.surface)

		surface_format := choose_swap_surface_format(swapchain_support.formats[:], swapchain_info.color_space, swapchain_info.format)
		present_mode   := choose_swap_present_mode(swapchain_support.present_modes[:], swapchain_info.present_mode)
		extent         := choose_swap_extent(swapchain_support.capabilities, device.window, device.window_type)

		image_count := swapchain_support.capabilities.minImageCount + 1

		if swapchain_support.capabilities.maxImageCount > 0 && image_count > swapchain_support.capabilities.maxImageCount {
			image_count = swapchain_support.capabilities.maxImageCount
		}

		swapchain_create_info := vk.SwapchainCreateInfoKHR {
			sType            = .SWAPCHAIN_CREATE_INFO_KHR,
			surface          = device.surface,
			minImageCount    = image_count,
			imageFormat      = surface_format.format,
			imageColorSpace  = surface_format.colorSpace,
			imageExtent      = extent,
			imageArrayLayers = 1,
			imageUsage       = { .COLOR_ATTACHMENT }, // this might be customizable later in the future
			preTransform     = swapchain_support.capabilities.currentTransform, // transforms applied to the images in the swapchain
			compositeAlpha   = { .OPAQUE },
			presentMode      = present_mode,
			clipped          = true,
			oldSwapchain     = {},
		}

		indices := Find_Queue_Families(device.physical_device, device.surface, device.supported_queues)

		queue_family_indices := [2]u32 { indices.graphics.?, indices.present.? }

		if indices.graphics.? != indices.present.? {
			swapchain_create_info.imageSharingMode      = .CONCURRENT
			swapchain_create_info.queueFamilyIndexCount = len(queue_family_indices)
			swapchain_create_info.pQueueFamilyIndices   = raw_data(&queue_family_indices)
		} else {
			swapchain_create_info.imageSharingMode = .EXCLUSIVE
		}

		if vk.CreateSwapchainKHR(device.logical_device, &swapchain_create_info, nil, &swapchain.internal) != vk.Result.SUCCESS {
			Print_Error("failed to create swapchain!")
			return 
		}

		vk.GetSwapchainImagesKHR(device.logical_device, swapchain.internal, &image_count, nil)
		swapchain.images = make([]vk.Image, image_count)
		vk.GetSwapchainImagesKHR(device.logical_device, swapchain.internal, &image_count, raw_data(swapchain.images))

		swapchain.image_format = surface_format.format
		swapchain.image_extent = extent
	}

	// set up image views of the swapchain
	{
		swapchain.image_views = make([]vk.ImageView, len(swapchain.images))

		ok := false
		for image_view, i in &swapchain.image_views {
			image_view, ok = create_image_view(device, swapchain.images[i], swapchain.image_format)

			if !ok do return
		}
	}

	// create render pass 
	{
		color_attachment := vk.AttachmentDescription {
			format         = swapchain.image_format,
			samples        = { ._1 },
			loadOp         = .CLEAR,
			storeOp        = .STORE,
			stencilLoadOp  = .DONT_CARE,
			stencilStoreOp = .DONT_CARE,
			initialLayout  = .UNDEFINED,
			finalLayout    = .PRESENT_SRC_KHR,
		}

		color_attachment_ref := vk.AttachmentReference {
			attachment = 0,
			layout     = .COLOR_ATTACHMENT_OPTIMAL,
		}

		subpass := vk.SubpassDescription {
			pipelineBindPoint    = .GRAPHICS,
			colorAttachmentCount = 1,
			pColorAttachments    = &color_attachment_ref,
		}

		subpass_dependency := vk.SubpassDependency {
			srcSubpass    = vk.SUBPASS_EXTERNAL,
			dstSubpass    = 0,
			srcStageMask  = { .COLOR_ATTACHMENT_OUTPUT },
			srcAccessMask = { .COLOR_ATTACHMENT_READ, },
			dstStageMask  = { .COLOR_ATTACHMENT_OUTPUT },
			dstAccessMask = { .COLOR_ATTACHMENT_WRITE },
		}

		renderpass_info := vk.RenderPassCreateInfo {
			sType           = .RENDER_PASS_CREATE_INFO,
			attachmentCount = 1,
			pAttachments    = &color_attachment,
			subpassCount    = 1,
			pSubpasses      = &subpass,
			dependencyCount = 1,
			pDependencies   = &subpass_dependency,
		}

		if vk.CreateRenderPass(device.logical_device, &renderpass_info, nil, &swapchain.render_pass) != vk.Result.SUCCESS {
			Print_Error("failed to create render pass!")
			return
		}
	}

	// set up image frame buffers 
	{
		swapchain.frame_buffers = make([]vk.Framebuffer, len(swapchain.images))

		for image_view, i in &swapchain.image_views {
			frame_buffer_info := vk.FramebufferCreateInfo {
				sType = .FRAMEBUFFER_CREATE_INFO,
				renderPass      = swapchain.render_pass,
				attachmentCount = 1,
				pAttachments    = &image_view,
				width           = swapchain.image_extent.width,
				height          = swapchain.image_extent.height,
				layers          = 1,
			}

			if vk.CreateFramebuffer(device.logical_device, &frame_buffer_info, nil, &swapchain.frame_buffers[i]) != vk.Result.SUCCESS {
				Print_Error("failed to create frame buffers!")
				return
			}		
		}
	}

	return
}

Delete_Swapchain :: proc(device: Device, swapchain: Swapchain) {
	for frame_buffer in swapchain.frame_buffers {
		vk.DestroyFramebuffer(device.logical_device, frame_buffer, nil)
	}

	for image_view in swapchain.image_views {
		vk.DestroyImageView(device.logical_device, image_view, nil)
	}

	vk.DestroyRenderPass(device.logical_device, swapchain.render_pass, nil)
	vk.DestroySwapchainKHR(device.logical_device, swapchain.internal, nil)
	delete(swapchain.images)
	delete(swapchain.image_views)
	delete(swapchain.frame_buffers)
}