# JAI vulkan binding generator

This repository contains JAI bindings for Vulkan as well as loading code and a generator.

Usage:
 * Download or copy `vulkan.jai` into your project's modules folder and `#import` it.
   It declares `#module_parameters`, so it must be imported as a module - it cannot be `#load`-ed;
 * Call the loader functions:
```jai
// Load the library and the global functions
if vk_initialize() != .SUCCESS  exit(-1);

instance: VkInstance;
// ... create instance code goes here

vk_load_instance_only(instance);

device: VkDevice;
// ... create device code goes here

vk_load_device(device);

#import "Basic";
#import "vulkan";
```

Vulkan code is under Khronos' license (see both the file and vk.xml headers).

For a concrete and compilable example, see: `example/info.jai`.

You can compile and run it with: `jai-linux example/info.jai +Autorun` and it should print some driver/GPU information.

The rest of the code is under a double license (see LICENSE.txt).

TL;DR: attribution is nice, but isn't required and you only need `vulkan.jai` to start using vulkan.

There are some alternatives like `vk_load_instance` if you don't want to load a device
separately or `vk_load_device_table` for multiple devices.

Those work similarly to volk and should be familiar to Vulkan developers.

However, you should only need the 3 functions above in 99% of cases.

## Why this project?

### How is this different from the built-in module

At the time of writing (July 2026) the built-in Vulkan module is based on an old
version of the headers.

Furthermore, it is generated from the C headers and not from the registry xml.

It doesn't provide default values nor the custom loading functions.

This library works like a combination of the C header + [Volk](https://github.com/zeux/volk) and the default values for
`sType` from the `.hpp` constructors.

### How is this different from other bindings

I had a quick look around, and at the time of writing other loaders were either
limited (e.g. generated from the C headers) or encumbered by complex licenses (permissive, but cumbersome).

I wanted something that was minimal, convenient and as easy to add to a project as the [stb libraries](https://github.com/nothings/stb).

## Run the generator

If you want to run the generator - maybe with an updated vk.xml - you can run:
```bash
jai-linux generator.jai
./bin/generator
```

On windows:
```batch
jai.exe generator.jai
bin/generator.exe
```

Note that this assumes the compiler is on the path.

The latest version of the registry xml can be found in this [Khronos repository](https://github.com/KhronosGroup/Vulkan-Headers/blob/main/registry/vk.xml).

