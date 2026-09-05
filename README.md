# JAI vulkan binding generator

This repository contains JAI bindings for Vulkan as well as loading code and a generator.

Note that VMA is also supported, see the VMA section below.

The prebuilt libraries are stored with [Git LFS](https://git-lfs.com), so
install it before cloning or you will get text pointer files instead.

Usage:
 * Download or copy `Vulkan.jai` into your project's modules folder and `#import` it.
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
#import "Vulkan";
```

There are some alternatives like `vk_load_instance` if you don't want to load a device
separately or `vk_load_device_table` for multiple devices.

Those work similarly to volk and should be familiar to Vulkan developers.

However, you should only need the 3 functions above in 99% of cases.

> [!WARNING]
> `#import "Vulkan";` will conflict with the built-in module from the compiler.
> If you are using custom import directories, make sure they precede the built-in
> one.

## Enumerate/get wrappers

The generated module also includes wrappers for the `vkEnumerate*` and `vkGet*`
functions that follow the two-call count/array idiom.

Those make use of Jai's context allocator and multiple return values.

You can replace calls of the form:
```jai
count1: u32;
vkEnumerateXXX(inst_or_device, *count1, null);
array1 := NewArray(count1, Type);
result := vkEnumerateXXX(inst_or_device, *count1, array1.data);

count2: u32;
vkGetXXX(inst_or_device, *count2, null);
array2 := NewArray(count2, Type);
vkGetXXX(inst_or_device, *count2, array2.data);
```

With a single call to:
```jai
result, array1 := vkEnumerateXXXArray(inst_or_device);
array2 := vkGetXXXArray(inst_or_device);
```

The `vkGet*` wrappers return only the slice, since those functions return `void`.

This also lets you override the allocator in the idiomatic Jai way:
```jai
result, array := vkEnumerateXXXArray(inst_or_device,, temp);
```

Credits to [vulkan-jai-bindings](https://github.com/drshapeless/vulkan-jai-binding/) for this idea.

## Examples

For concrete, compilable examples see the `example` folder:

 * `example/info.jai` prints driver and GPU information;
 * `example/use_vma.jai` additionally creates a VMA allocator.

Both are built by a single metaprogram, from the repository root:

```
jai-linux example/build.jai
```

That produces `example/info` and `example/use_vma`, which you can run directly.

The examples also cross-compile to Android. From inside `example`:

```
jai-linux -import_dir .. info.jai +Android/Toolchain
```

Note that `-import_dir` has to come before the source file, because the Android
plugin consumes every argument that follows it. This produces an arm64 shared
library under `AndroidProject/app/src/main/jniLibs/`. To actually launch on a
device the program additionally needs an Android entry point:

```jai
#if OS == .ANDROID  #import "Android"()(main);
```

## VMA

A [Vulkan Memory Allocator](https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator)
module is included alongside Vulkan. It is optional: if you only want Vulkan,
copy `Vulkan.jai` and ignore the rest.

To use it, copy the whole `VkMemAlloc` directory into your modules folder and
`#import "VkMemAlloc";`.

If you move `Vulkan.jai` to a different module directory or name, you'll need to
change the import at the end of `vma_<platform>.jai`.

VMA is C++, so the module ships a prebuilt library per platform. Nothing needs
to sit next to your executable on Linux, macOS or Windows; on Android the `.so`
goes in the apk like any other native library. The only extra runtime
dependency is the platform C++ runtime, which is a system library everywhere it
is needed at all.

The library is built with `VK_NO_PROTOTYPES`, so VMA never links Vulkan
directly - you must fill in `VmaAllocatorCreateInfo.pVulkanFunctions`. See
`example/use_vma.jai` for a complete allocator setup.

## Licenses

Vulkan code is under Khronos' license (see both the file and vk.xml headers).

VMA itself is MIT licensed (Copyright (c) 2017-2026 Advanced Micro Devices,
Inc.), see `src/VulkanMemoryAllocator-<version>/LICENSE.txt`.

The rest of the code is under a double license (see LICENSE.txt).

TL;DR: attribution is nice, but isn't required and you only need `Vulkan.jai` to start using vulkan.

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

Regenerating the VMA bindings additionally needs:

 * The VMA source, which is not vendored. Download the release matching
   `SOURCE_PATH` in `vma_generator.jai` and unpack it under `src/`;
 * A C++ compiler, since the generator also builds the VMA library
   (clang on Unix, MSVC on Windows). Without the source the Vulkan bindings
   are still generated and VMA generation is skipped.

To cross-compile the VMA library and bindings for Android, pass `-android`:

```bash
./bin/generator -android
```

This needs the Android NDK, found through `ANDROID_NDK_HOME` or
`$ANDROID_HOME/ndk`. It builds both the `arm64` and `x64` ABIs.

The latest version of the registry xml can be found in this [Khronos repository](https://github.com/KhronosGroup/Vulkan-Headers/blob/main/registry/vk.xml).

## Other similar projects

I was aware of the Osor bindings when I started this generator, but I wanted something easier to include.

I have since run into other similar projects.

 * [Osor Vulkan](https://codeberg.org/osor_io/osor_vulkan) - Apache 2.0 licensed, but quite popular and mentioned in the compiler docs. Generates multiple files;
 * [Vulkan JAI Bindings](https://github.com/drshapeless/vulkan-jai-binding) - Multiple file output, but likely a more complete generator;
