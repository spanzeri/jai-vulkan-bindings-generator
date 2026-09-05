/*
 * VMA binding generator for: JAI vulkan binding generator.
 * For license information, see the accompanying: LICENSE.txt file.
 */

//
// This generator uses the clang tooling provided by the compiler (compared to
// the main vulkan generator that is based on the registry XML).
//

SOURCE_PATH :: "src/VulkanMemoryAllocator-3.4.0";

#if OS == .WINDOWS {
    // Reads VULKAN_SDK at the time the generator actually runs (not baked in at
    // generator build time), since the SDK location/version is a property of the
    // machine running the generator, not the machine that built it.
    get_vulkan_sdk :: () -> string, bool {
        VulkanSdk := to_string(Win.getenv("VULKAN_SDK".data));
        if !VulkanSdk {
            log_error(" ! ERROR: The VULKAN_SDK environment variable is not set. Install the Vulkan SDK from https://vulkan.lunarg.com/ (its installer sets VULKAN_SDK) and restart your shell.");
            return "", false;
        }
        return VulkanSdk, true;
    }
} else {
    get_vulkan_sdk :: () -> string, bool { return "", false; }
}

// Android is always a cross-target, so the target can't come from #if OS here.
generate_vma_bindings :: (TargetOs := OS, TargetCpu := CPU) -> bool {
    if !is_directory(SOURCE_PATH) {
        log_error(" ! ERROR: VMA source code should be provided in src/vma. Skipping VMA generation...");
        return false;
    }

    if !build_vma_libraries(TargetOs, TargetCpu) {
        log_error(" ! ERROR: Failed to build VMA libraries. Skipping VMA generation...");
        return false;
    }

    Options: Generate_Bindings_Options;
    Options.os  = TargetOs;
    Options.cpu = TargetCpu;

    {
        using Options;

        array_add(*include_paths, tprint("%/include", SOURCE_PATH));
        #if OS == .WINDOWS {
            if TargetOs == .WINDOWS {
                VulkanSdk, VulkanSdkOk := get_vulkan_sdk();
                if !VulkanSdkOk return false;
                // system_include_paths defaults to get_default_system_include_paths()
                // only when left empty, so seed it with those defaults ourselves
                // before adding the SDK path.
                array_add(*system_include_paths, ..get_default_system_include_paths(TargetOs, TargetCpu));
                array_add(*system_include_paths, tprint("%/Include", VulkanSdk));
            }
        }
        array_add(*source_files, "vk_mem_alloc.h");
        array_add(*libraries, Library.{ "libvma", "" });

        array_add(*library_search_paths, vma_library_directory(TargetOs, TargetCpu));

        array_add(*extra_clang_arguments, "-x", "c");

        c_enum_emulation              = false;
        strip_enum_prefixes           = true;
        auto_detect_enum_prefixes     = true;
        alias_original_enum_names     = true;
        generate_library_declarations = false;

        generate_compile_time_struct_checks = true;
        log_stripped_declarations           = false;

        visitor                              = vma_visitor;
        convert_macro_value_to_enum_callback = vma_macro_to_enum;
        will_print_bindings                  = vma_fixups;

        strip_flags = .FUNCTIONS_WITH_VALIST;

        // Force the callaback for macros to get called
        array_add(*generate_enums_from_macros_with_prefixes, "NOT_A_REAL_MACRO_BUT_WE_NEED_ONE");
    }

    BindingName: string;
    if TargetOs == {
        case .LINUX;   BindingName = "vma_linux.jai";
        case .WINDOWS; BindingName = "vma_windows.jai";
        case .MACOS;   BindingName = "vma_macos.jai";
        case .ANDROID; BindingName = "vma_android.jai";
        case; log_error(" ! ERROR: VMA bindings are not supported on %", TargetOs); return false;
    }

    return generate_bindings(Options, tprint("VkMemAlloc/%", BindingName));
}

//
// Header generator
//

vma_visitor :: (Decl: *Declaration, ParenDecl: *Declaration) -> Declaration_Visit_Result {
    if Decl.kind == .ENUM {
        E := cast(*Enum)Decl;
        if ends_with(Decl.name, "FlagBits") {
            E.flags |= .IS_ENUM_FLAGS;
            E.flags |= .VALUES_IN_HEX;
        }
    }

    return .RECURSE;
}

macro_enum :: struct {
    Prefix:     string;
    EnumName:   string;
}

MACRO_TO_ENUM :: macro_enum.[
];

vma_macro_to_enum :: (Decl: *Declaration) -> string {
    for MACRO_TO_ENUM {
        if begins_with(Decl.name, it.Prefix) {
            return it.EnumName;
        }
    }
    return "";
}

// VMA spells every flag type as a "VmaXFlagBits" enum plus a separate
// "typedef VkFlags VmaXFlags" that all the structs and functions actually use.
// Retarget each such typedef at its enum so the alias carries the flag type
// rather than a bare u32 (this is what the registry-based Vulkan generator
// emits for VkXFlags too).
vma_fixups :: () {
    Members := context.generator.global_scope.members;

    // Every VMA enum carries a *_MAX_ENUM = 0x7FFFFFFF sentinel that only exists to
    // pin the C storage size. Dropping it here rather than in the visitor keeps the
    // detected enum prefixes (and so every other member's name) exactly as they are.
    for Member : Members {
        if Member.kind != .ENUM continue;
        for (cast(*Enum) Member).enumerates {
            if ends_with(it.name, "_MAX_ENUM") it.decl_flags |= .OMIT_FROM_OUTPUT;
        }
    }

    for Alias : Members {
        if Alias.kind != .TYPEDEF || !ends_with(Alias.name, "Flags") continue;

        Base := Alias.name;
        Base.count -= "Flags".count;
        BitsName := tprint("%FlagBits", Base);

        for Members {
            if it.kind == .ENUM && it.name == BitsName {
                Alias.type = create_type_of_enum(xx it);
                break;
            }
        }
    }
}

//
// Library builder
//

vma_library_directory :: (TargetOs: Operating_System_Tag, TargetCpu: CPU_Tag) -> string {
    if TargetOs == {
        case .LINUX;   return "VkMemAlloc/linux";
        case .WINDOWS; return "VkMemAlloc/windows";
        case .MACOS;   return "VkMemAlloc/macos";
        // Android ships one library per ABI inside the apk.
        case .ANDROID; return ifx TargetCpu == .ARM64 then "VkMemAlloc/android/arm64" else "VkMemAlloc/android/x64";
        case;          return "";
    }
}

build_vma_libraries :: (TargetOs: Operating_System_Tag, TargetCpu: CPU_Tag) -> bool {
    Directory := vma_library_directory(TargetOs, TargetCpu);
    if !Directory {
        log_error(" ! ERROR: No VMA library layout for %", TargetOs);
        return false;
    }
    make_directory_if_it_does_not_exist(Directory, recursive=true);

    if TargetOs == {
        case .LINUX;
            Extra :: string.[
                #run tprint("-I%/%", SOURCE_PATH, "include"),
                "-fno-exceptions",
                "-fno-rtti",
            ];
            return build_cpp_static_lib(tprint("%/libvma", Directory), "src/vma.cpp", extra=Extra);

        case .WINDOWS;
            VulkanSdk, VulkanSdkOk := get_vulkan_sdk();
            if !VulkanSdkOk return false;

            // Not a constant array (Extra :: ...) like the other platforms, since one
            // entry depends on the VULKAN_SDK environment variable read above.
            Extra := string.[
                #run tprint("-I%/%", SOURCE_PATH, "include"),
                "/std:c++17",
                // Static CRT, so the library carries the C++ runtime instead of
                // depending on msvcp140.dll.
                "/MT",
                "/EHs-c-",
                "/GR-",
                "/D_HAS_EXCEPTIONS=0",
                tprint("/I%/Include", VulkanSdk),
            ];
            return build_cpp_static_lib(tprint("%/libvma", Directory), "src/vma.cpp", extra=Extra);

        case .MACOS;
            Extra :: string.[
                #run tprint("-I%/%", SOURCE_PATH, "include"),
                "-x", "c++",
                "-std=c++17",
                "-fno-exceptions",
                "-fno-rtti",
            ];
            // Builds both slices with the right -mmacos-version-min and lipos them together.
            return build_universal_macos_binary(tprint("%/libvma", Directory), "src/vma.cpp", type=.STATIC_LIBRARY, extra=Extra);

        case .ANDROID;
            Triple, TripleWithSdk := get_android_target_triple(TargetCpu);
            Extra: [..] string;
            Extra.allocator = temp;
            array_add(*Extra,
                tprint("-I%/include", SOURCE_PATH),
                "-x", "c++",
                "-std=c++17",
                "-fno-exceptions",
                "-fno-rtti",
                "-target", TripleWithSdk,
                // The NDK's libc++_shared.so is not present on the device, so fold
                // the C++ runtime into the library rather than shipping another .so.
                "-static-libstdc++",
                "-Wl,-soname,libvma.so",
            );
            return build_cpp_dynamic_lib(tprint("%/libvma", Directory), "src/vma.cpp", target=.ANDROID, extra=Extra);

        case;
            log_error(" ! ERROR: Implement VMA compilation for %", TargetOs);
            return false;
    }
}

#import "Bindings_Generator";
#import "File";
#import "File_Utilities";
#import "BuildCpp";
#import "Android/Toolchain";
#if OS == .WINDOWS Win :: #import "Windows";

