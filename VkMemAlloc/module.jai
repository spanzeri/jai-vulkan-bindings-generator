#if OS == .WINDOWS {
    #load "vma_windows.jai";
    libvma :: #library,no_dll "windows/libvma";
    // Built with /MT (static CRT): libcmt.lib covers the C runtime already, but
    // the C++ runtime support functions (std::mutex/shared_mutex internals,
    // __std_exception_throw helpers, etc.) live in a separate static lib that
    // isn't linked by default.
    #library,system,link_always "libcpmt";
} else #if OS == .LINUX {
    #load "vma_linux.jai";
    libvma :: #library,no_dll "linux/libvma";
    #library,system,link_always "libstdc++";
    #library,system,link_always "libpthread";
} else #if OS == .MACOS {
    #load "vma_macos.jai";
    libvma :: #library,no_dll "macos/libvma";
    #library,system,link_always "libc++";
} else #if OS == .ANDROID {
    #load "vma_android.jai";
    // Shipped per-abi inside the apk; the C++ runtime is already folded in.
    #if CPU == .ARM64 {
        libvma :: #library "android/arm64/libvma";
    } else #if CPU == .X64 {
        libvma :: #library "android/x64/libvma";
    } else {
        #assert false "Unsupported Android ABI";
    }
}

