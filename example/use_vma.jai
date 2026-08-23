f32 :: float32;
 
main :: () {
    if vk_initialize() != .SUCCESS {
        log_error("Failed to load the Vulkan library.");
        return;
    }
    defer vk_finalize();

    v := vk_get_instance_version();
    print("Vulkan loader version: %.%.%\n", v >> 22, (v >> 12) & 0x3ff, v & 0xfff);

    // ---- instance ----
    app: VkApplicationInfo;
    app.pApplicationName = "jai-vma-example";
    app.apiVersion       = make_version(1, 0, 0);

    instance_info: VkInstanceCreateInfo;
    instance_info.pApplicationInfo = *app;

    instance: VkInstance;
    if vkCreateInstance(*instance_info, null, *instance) != .SUCCESS {
        log_error("vkCreateInstance failed.");
        return;
    }
    defer vkDestroyInstance(instance, null);

    vk_load_instance(instance);

    // ---- physical device ----
    result, gpus := vkEnumeratePhysicalDevicesArray(instance);
    defer array_free(gpus);
    if result != .SUCCESS || gpus.count == 0 {
        log_error("No Vulkan physical devices found.");
        return;
    }

    gpu := gpus[0];

    // ---- logical device ----
    priority: f32 = 1.0;
    queue_info: VkDeviceQueueCreateInfo;
    queue_info.queueFamilyIndex = 0;
    queue_info.queueCount       = 1;
    queue_info.pQueuePriorities  = *priority;

    device_info: VkDeviceCreateInfo;
    device_info.queueCreateInfoCount = 1;
    device_info.pQueueCreateInfos    = *queue_info;

    device: VkDevice;
    if vkCreateDevice(gpu, *device_info, null, *device) != .SUCCESS {
        log_error("vkCreateDevice failed.");
        return;
    }
    defer vkDestroyDevice(device, null);

    vk_load_device(device);

    // ---- VMA allocator ----
    vulkan_functions: VmaVulkanFunctions;
    vulkan_functions.vkGetInstanceProcAddr = vkGetInstanceProcAddr;
    vulkan_functions.vkGetDeviceProcAddr   = vkGetDeviceProcAddr;
    vulkan_functions.vkGetPhysicalDeviceProperties        = vkGetPhysicalDeviceProperties;
    vulkan_functions.vkGetPhysicalDeviceMemoryProperties  = vkGetPhysicalDeviceMemoryProperties;
    vulkan_functions.vkAllocateMemory                     = vkAllocateMemory;
    vulkan_functions.vkFreeMemory                         = vkFreeMemory;
    vulkan_functions.vkMapMemory                          = vkMapMemory;
    vulkan_functions.vkUnmapMemory                        = vkUnmapMemory;
    vulkan_functions.vkFlushMappedMemoryRanges             = vkFlushMappedMemoryRanges;
    vulkan_functions.vkInvalidateMappedMemoryRanges        = vkInvalidateMappedMemoryRanges;
    vulkan_functions.vkBindBufferMemory                    = vkBindBufferMemory;
    vulkan_functions.vkBindImageMemory                     = vkBindImageMemory;
    vulkan_functions.vkGetBufferMemoryRequirements         = vkGetBufferMemoryRequirements;
    vulkan_functions.vkGetImageMemoryRequirements          = vkGetImageMemoryRequirements;
    vulkan_functions.vkCreateBuffer                        = vkCreateBuffer;
    vulkan_functions.vkDestroyBuffer                       = vkDestroyBuffer;
    vulkan_functions.vkCreateImage                         = vkCreateImage;
    vulkan_functions.vkDestroyImage                        = vkDestroyImage;
    vulkan_functions.vkCmdCopyBuffer                       = vkCmdCopyBuffer;
    vulkan_functions.vkGetBufferMemoryRequirements2KHR     = cast(PFN_vkGetBufferMemoryRequirements2KHR)
        vkGetDeviceProcAddr(device, "vkGetBufferMemoryRequirements2");
    vulkan_functions.vkGetImageMemoryRequirements2KHR      = cast(PFN_vkGetImageMemoryRequirements2KHR)
        vkGetDeviceProcAddr(device, "vkGetImageMemoryRequirements2");
    vulkan_functions.vkBindBufferMemory2KHR                = cast(PFN_vkBindBufferMemory2KHR)
        vkGetDeviceProcAddr(device, "vkBindBufferMemory2");
    vulkan_functions.vkBindImageMemory2KHR                 = cast(PFN_vkBindImageMemory2KHR)
        vkGetDeviceProcAddr(device, "vkBindImageMemory2");
    vulkan_functions.vkGetPhysicalDeviceMemoryProperties2KHR = cast(PFN_vkGetPhysicalDeviceMemoryProperties2KHR)
        vkGetDeviceProcAddr(device, "vkGetPhysicalDeviceMemoryProperties2");
    vulkan_functions.vkGetDeviceBufferMemoryRequirements     = cast(PFN_vkGetDeviceBufferMemoryRequirementsKHR)
        vkGetDeviceProcAddr(device, "vkGetDeviceBufferMemoryRequirements");
    vulkan_functions.vkGetDeviceImageMemoryRequirements      = cast(PFN_vkGetDeviceImageMemoryRequirementsKHR)
        vkGetDeviceProcAddr(device, "vkGetDeviceImageMemoryRequirements");
    vulkan_functions.vkGetMemoryWin32HandleKHR               = null;
    vulkan_functions.vkGetPhysicalDeviceProperties2KHR       = cast(PFN_vkGetPhysicalDeviceProperties2KHR)
        vkGetDeviceProcAddr(device, "vkGetPhysicalDeviceProperties2");

    allocator_info: VmaAllocatorCreateInfo;
    allocator_info.flags                          = 0;
    allocator_info.physicalDevice                   = gpu;
    allocator_info.device                           = device;
    allocator_info.preferredLargeHeapBlockSize      = 0;
    allocator_info.pAllocationCallbacks             = null;
    allocator_info.pDeviceMemoryCallbacks           = null;
    allocator_info.pHeapSizeLimit                   = null;
    allocator_info.pVulkanFunctions                 = *vulkan_functions;
    allocator_info.instance                           = instance;
    allocator_info.vulkanApiVersion                   = 0;
    allocator_info.pTypeExternalMemoryHandleTypes   = null;

    allocator: VmaAllocator;
    result = vmaCreateAllocator(*allocator_info, *allocator);
    if result != .SUCCESS {
        log_error("vmaCreateAllocator failed: %", result);
        return;
    }
    defer vmaDestroyAllocator(allocator);

    print("\nVMA allocator created successfully.\n");
}

make_version :: (major: u32, minor: u32, patch: u32) -> u32 {
    return (major << 22) | (minor << 12) | patch;
}

#import "Basic";
#import "Vulkan";       // This is our vulkan module from the top level directory
#import "VkMemAlloc";

