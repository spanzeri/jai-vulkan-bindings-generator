/*
Minimal Vulkan example: initialise the loader, create an instance and a logical
device on the first physical device, then print some information about it.

Build (native):
    jai-linux info.jai
Build (cross compile every supported OS, type-check only):
    jai-linux info.jai - cross
*/

#import,file "../vulkan.jai";

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
    app.pApplicationName = "jai-vulkan-example";
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

    props: VkPhysicalDeviceProperties;
    vkGetPhysicalDeviceProperties(gpu, *props);

    print("\nPhysical device 0 of %:\n", gpus.count);
    print("  name         : %\n", to_string(props.deviceName.data));
    print("  type         : %\n", props.deviceType);
    print("  api version  : %.%.%\n", props.apiVersion >> 22, (props.apiVersion >> 12) & 0x3ff, props.apiVersion & 0xfff);
    print("  vendor / dev : 0x% / 0x%\n", formatInt(props.vendorID, base = 16), formatInt(props.deviceID, base = 16));

    mem: VkPhysicalDeviceMemoryProperties;
    vkGetPhysicalDeviceMemoryProperties(gpu, *mem);
    total: u64;
    for 0..mem.memoryHeapCount - 1 {
        heap := mem.memoryHeaps[it];
        if heap.flags & .DEVICE_LOCAL_BIT  total += heap.size;
    }
    print("  device-local : % MiB\n", total / (1024 * 1024));

    // ---- pick a graphics queue family ----
    families := vkGetPhysicalDeviceQueueFamilyPropertiesArray(gpu);
    defer array_free(families);

    graphics_family: u32 = 0xffff_ffff;
    for 0..families.count - 1 {
        if families[it].queueFlags & .GRAPHICS_BIT {
            graphics_family = cast(u32) it;
            break;
        }
    }
    if graphics_family == 0xffff_ffff {
        log_error("No graphics queue family.");
        return;
    }
    print("  graphics fam : % (% queues)\n", graphics_family, families[graphics_family].queueCount);

    // ---- logical device ----
    priority: float32 = 1.0;
    queue_info: VkDeviceQueueCreateInfo;
    queue_info.queueFamilyIndex = graphics_family;
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

    queue: VkQueue;
    vkGetDeviceQueue(device, graphics_family, 0, *queue);

    print("\nDevice created. Graphics queue loaded via device table: %\n", queue != null);
    print("vkCmdDraw resolved through vkGetDeviceProcAddr: %\n", vkCmdDraw != null);
}

make_version :: (major: u32, minor: u32, patch: u32) -> u32 {
    return (major << 22) | (minor << 12) | patch;
}

#import "Basic";

// ---- optional cross-compile driver: `jai-linux info.jai - cross` ----
#run {
    opts := get_build_options();

    // Spawned child workspaces (below) are NO_OUTPUT: bail so they don't recurse.
    if opts.output_type == .NO_OUTPUT return;

    is_cross := false;
    for opts.compile_time_command_line  if it == "cross"  is_cross = true;
    if !is_cross return;

    set_build_options_dc(.{do_output = false});
    for target: Operating_System_Tag.[.WINDOWS, .LINUX, .MACOS, .ANDROID] {
        w := compiler_create_workspace(tprint("info-%", target));
        child := get_build_options(w);
        child.output_type = .NO_OUTPUT;
        child.os_target   = target;
        if target == .ANDROID  child.cpu_target = .X64;
        set_build_options(child, w);
        add_build_file(#file, w);
    }

    #import "Compiler";
}

