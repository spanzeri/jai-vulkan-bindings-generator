/*
 * Binding source emitter for: JAI vulkan binding generator.
 * For license information, see the accompanying: LICENSE.txt file.
 */

emit_registry :: (R: registry) -> string {
    SB: String_Builder;

    if R.Copyright.count > 0 {
        append(*SB, "/*\n");
        append(*SB, R.Copyright);
        append(*SB, "\n*/\n\n");
    }
    append(*SB, "// Generated Vulkan bindings. Do not edit by hand.\n");
    append(*SB, "// See: https://github.com/spanzeri/jai-vulkan-bindings-generator\n\n");

    emit_module_parameters(*SB, R);
    emit_version(*SB, R);
    emit_constants(*SB, R);
    emit_types(*SB, R);
    emit_commands(*SB, R);
    emit_enumerators(*SB, R);
    emit_loader(*SB, R);

    // Append basic at the end since that is the convention in JAI
    append(*SB, "#import \"Basic\";\n\n");

    return builder_to_string(*SB);
}

#scope_file

emit_module_parameters :: (SB: *String_Builder, R: registry) {
    Protects: [..]string;
    defer array_free(Protects);
    for Val, Name: R.Platforms  array_add(*Protects, Val);
    quick_sort(Protects, compare_strings);

    append(SB, "#module_parameters () (\n");
    for Protects {
        Sep := ifx it_index == Protects.count - 1 then "" else ",";
        print_to_builder(SB, "    % := %%\n", it, platform_default_expr(it), Sep);
    }
    append(SB, ");\n\n");
}

emit_version :: (SB: *String_Builder, R: registry) {
    append(SB, VERSION_HELPERS);

    Major, Minor := 0;
    for R.ApiVersions {
        print_to_builder(SB, "VK_API_VERSION_%1_%2 :: #run VK_MAKE_API_VERSION(0, %1, %2, 0);\n", it.Major, it.Minor);
        if it.Major > Major || (it.Major == Major && it.Minor > Minor) {
            Major = it.Major;
            Minor = it.Minor;
        }
    }

    print_to_builder(SB, "\nVK_HEADER_VERSION :: %;", R.HeaderVersion);
    print_to_builder(
        SB,
        "\nVK_HEADER_VERSION_COMPLETE :: #run VK_MAKE_API_VERSION(0, %1, %2, VK_HEADER_VERSION);\n\n",
        Major, Minor,
    );
}

VERSION_HELPERS :: #string DONE
VK_MAKE_API_VERSION :: inline (variant: u32, major: u32, minor: u32, patch: u32) -> u32 {
    return (variant << 29) | (major << 22) | (minor << 12) | patch;
}

VK_API_VERSION_VARIANT :: inline (version: u32) -> u32 { return (version >> 29);         }
VK_API_VERSION_MAJOR   :: inline (version: u32) -> u32 { return (version >> 22) &  0x7F; }
VK_API_VERSION_MINOR   :: inline (version: u32) -> u32 { return (version >> 12) & 0x3FF; }
VK_API_VERSION_PATCH   :: inline (version: u32) -> u32 { return (version >>  0) & 0xFFF; }
DONE;

platform_default_expr :: (Protect: string) -> string {
    if Protect == {
        case "VK_USE_PLATFORM_WIN32_KHR";       return "OS == .WINDOWS";
        case "VK_USE_PLATFORM_XLIB_KHR";        #through;
        case "VK_USE_PLATFORM_XLIB_XRANDR_EXT"; #through;
        case "VK_USE_PLATFORM_XCB_KHR";         #through;
        case "VK_USE_PLATFORM_WAYLAND_KHR";     return "OS == .LINUX";
        case "VK_USE_PLATFORM_ANDROID_KHR";     return "OS == .ANDROID";
        case "VK_USE_PLATFORM_METAL_EXT";       return "OS == .MACOS || OS == .IOS";
        case "VK_USE_PLATFORM_MACOS_MVK";       return "OS == .MACOS";
        case "VK_USE_PLATFORM_IOS_MVK";         return "OS == .IOS";
    }
    return "false";
}

emit_constants :: (SB: *String_Builder, R: registry) {
    for R.Constants {
        Value := jai_constant_value(it);
        if Value.count == 0 continue;
        print_to_builder(SB, "% :: %;%\n", it.Name, Value, comment_suffix(it.Comment));
    }
    append(SB, "\n");
}

comment_suffix :: (Comment: string) -> string {
    if Comment.count == 0 return "";
    return tprint(" // %", clean_comment(Comment));
}

clean_comment :: (Comment: string) -> string {
    Text := trim(Comment, "/ \t\n");
    Out := alloc_string(Text.count);
    for 0..Text.count - 1  Out[it] = ifx Text[it] == #char "\n" then #char " " else Text[it];
    return trim_right(Out, " ");
}

emit_types :: (SB: *String_Builder, R: registry) {
    emit_external_forward_decls(SB, R);

    KnownEnumValues: Table(string, bool);
    defer deinit(*KnownEnumValues);
    for E: R.Enums  for V: E.Values  table_set(*KnownEnumValues, V.Name, true);

    for R.Enums  emit_enum(SB, it);

    for R.Types {
        if it.Category == {
            case .BASETYPE;    emit_basetype(SB, it);
            case .HANDLE;      emit_handle(SB, it);
            case .BITMASK;     emit_bitmask(SB, it, R);
            case .FUNCPOINTER; emit_funcpointer(SB, it);
            case .STRUCT;      #through;
            case .UNION;       emit_struct(SB, it, *KnownEnumValues);
            case .ALIAS;       emit_alias(SB, it);
            case .ENUM;        if !table_contains(*R.EnumIndex, it.Name) print_to_builder(SB, "% :: enum s32 {}\n\n", it.Name);
        }
    }
}

emit_external_forward_decls :: (SB: *String_Builder, R: registry) {
    Defined: Table(string, bool);
    defer deinit(*Defined);
    for R.Types  table_set(*Defined, it.Name, true);
    for R.Enums  table_set(*Defined, it.Name, true);
    for PRIMITIVE_C_TYPES  table_set(*Defined, it, true);

    External: Table(string, bool);
    defer deinit(*External);

    for T: R.Types {
        if T.Category == {
            case .STRUCT;      #through;
            case .UNION;       for M: T.Members  collect_external(*Defined, *External, M.Type.Base);
            case .FUNCPOINTER;
                collect_external(*Defined, *External, T.ReturnType.Base);
                for M: T.Members  collect_external(*Defined, *External, M.Type.Base);
            case .ALIAS;       collect_external(*Defined, *External, T.Alias);
        }
    }

    for C: R.Commands {
        if !C.Required continue;
        collect_external(*Defined, *External, C.ReturnType.Base);
        for P: C.Params  collect_external(*Defined, *External, P.Type.Base);
    }

    if External.count == 0 return;
    for Val, Name: External {
        Underlying := external_underlying(Name);
        if Underlying.count > 0  print_to_builder(SB, "% :: %; // platform type\n", Name, Underlying);
        else                     print_to_builder(SB, "% :: struct {} // external type\n", Name);
    }
    append(SB, "\n");
}

external_underlying :: (Name: string) -> string {
    if Name == {
        case "HWND";                   #through;
        case "HINSTANCE";              #through;
        case "HMONITOR";               #through;
        case "HANDLE";                 #through;
        case "LPCWSTR";                #through;
        case "NvSciSyncObj";           #through;
        case "NvSciBufObj";            #through;
        case "NvSciSyncAttrList";      #through;
        case "NvSciBufAttrList";
            return "*void";

        case "DWORD";                  #through;
        case "xcb_window_t";           #through;
        case "xcb_visualid_t";         #through;
        case "zx_handle_t";            #through;
        case "GgpStreamDescriptor";    #through;
        case "StdVideoH264ProfileIdc"; #through;
        case "StdVideoH264LevelIdc";   #through;
        case "StdVideoH265ProfileIdc"; #through;
        case "StdVideoH265LevelIdc";   #through;
        case "StdVideoAV1Profile";     #through;
        case "StdVideoAV1Level";       #through;
        case "StdVideoVP9Profile";     #through;
        case "StdVideoVP9Level";
            return "u32";

        case "Window";                 #through;
        case "VisualID";               #through;
        case "RROutput";               #through;
        case "GgpFrameToken";
            return "u64";
    }
    return "";
}

collect_external :: (Defined: *Table(string, bool), External: *Table(string, bool), Base: string) {
    if Base.count == 0 return;
    if table_contains(Defined, Base) return;
    if table_contains(External, Base) return;
    table_add(External, Base, true);
}

enum_decl_line :: struct {
    Full:    string;
    Short:   string;
    Value:   string;
    Comment: string;
}

emit_enum :: (SB: *String_Builder, E: vk_enum) {
    if E.IsBitmask  print_to_builder(SB, "% :: enum_flags % {\n", E.Name, ifx E.Bitwidth == 64 then "u64" else "u32");
    else            print_to_builder(SB, "% :: enum s32 {\n", E.Name);

    Prefix := common_prefix(E);

    Lines: [..]enum_decl_line;
    defer array_free(Lines);
    Seen: Table(string, bool);
    defer deinit(*Seen);

    for E.Values {
        if table_contains(*Seen, it.Name) continue;
        table_add(*Seen, it.Name, true);
        Value := ifx E.IsBitmask then tprint("0x%", formatInt(cast(u64) it.Value, base = 16)) else tprint("%", it.Value);
        array_add(*Lines, .{ Full = it.Name, Short = short_name(it.Name, Prefix), Value = Value, Comment = it.Comment });
    }

    for Lines {
        Name := ifx it.Short.count > 0 then it.Short else it.Full;
       print_to_builder(SB, "    % :: %;%\n", Name, it.Value, comment_suffix(it.Comment));
    }

    // separate short and long names
    append(SB, #char "\n");

    for Lines {
        if it.Short.count > 0 && it.Short != it.Full  print_to_builder(SB, "    % :: %;\n", it.Full, it.Short);
    }

    append(SB, "}\n\n");
}

common_prefix :: (E: vk_enum) -> string {
    Prefix: string;
    First := true;
    for E.Values {
        if it.Alias.count > 0 continue;
        if First { Prefix = it.Name; First = false; continue; }
        Prefix = shared_prefix(Prefix, it.Name);
    }
    Cut := last_index(Prefix, #char "_");
    if Cut == -1 return "";
    return slice(Prefix, 0, Cut + 1);
}

short_name :: (Full: string, Prefix: string) -> string {
    if Prefix.count == 0 || !begins_with(Full, Prefix) return "";
    S := slice(Full, Prefix.count, Full.count - Prefix.count);
    if S.count == 0 return "";
    if S[0] >= #char "0" && S[0] <= #char "9"  return tprint("_%", S);
    return S;
}

shared_prefix :: (A: string, B: string) -> string {
    N := min(A.count, B.count);
    I := 0;
    while I < N && A[I] == B[I]  I += 1;
    return slice(A, 0, I);
}

last_index :: (S: string, C: u8) -> int {
    I := S.count - 1;
    while I >= 0 {
        if S[I] == C return I;
        I -= 1;
    }
    return -1;
}

emit_basetype :: (SB: *String_Builder, T: vk_type) {
    if T.BaseType.count == 0 {
        print_to_builder(SB, "% :: struct {}\n\n", T.Name);
    }
    else {
        print_to_builder(SB, "% :: %;\n\n", T.Name, jai_base_type(T.BaseType));
    }
}

emit_handle :: (SB: *String_Builder, T: vk_type) {
    if T.Dispatchable {
        print_to_builder(SB, "%1_T :: struct {}\n%1 :: *%1_T;\n\n", T.Name);
    }
    else {
        print_to_builder(SB, "% :: #type,distinct u64;\n\n", T.Name);
    }
}

emit_bitmask :: (SB: *String_Builder, T: vk_type, R: registry) {
    if T.FlagBits.count > 0 && table_contains(*R.EnumIndex, T.FlagBits) {
        print_to_builder(SB, "% :: %;\n\n", T.Name, T.FlagBits);
    }
    else {
        Underlying := ifx T.Flag64 then "VkFlags64" else "VkFlags";
        print_to_builder(SB, "% :: %;\n\n", T.Name, Underlying);
    }
}

emit_funcpointer :: (SB: *String_Builder, T: vk_type) {
    print_to_builder(SB, "% :: #type (", T.Name);
    for T.Members {
        if it_index > 0 append(SB, ", ");
        Name := ifx it.Name.count > 0 then jai_ident(it.Name) else tprint("a%", it_index);
        print_to_builder(SB, "%: %", Name, jai_param_type(it.Type));
    }
    print_to_builder(SB, ") -> % #c_call;\n\n", jai_type(T.ReturnType));
}

bitfield_accessor :: struct {
    Field:       string;
    Storage:     string;
    StorageType: string;
    ValueType:   string;
    Offset:      int;
    Bits:        int;
}

emit_struct :: (SB: *String_Builder, T: vk_type, KnownEnumValues: *Table(string, bool)) {
    if T.Comment.count > 0  print_to_builder(SB, "// %\n", clean_comment(T.Comment));
    Keyword := ifx T.Category == .UNION then "union" else "struct";
    print_to_builder(SB, "% :: % {\n", T.Name, Keyword);

    Accessors: [..]bitfield_accessor;
    defer array_free(Accessors);
    UnitCount := 0;

    I := 0;
    while I < T.Members.count {
        M := T.Members[I];
        if M.Type.BitfieldBits > 0 {
            Width   := base_bit_width(M.Type.Base);
            Storage := ifx UnitCount == 0 then "__bitfield" else tprint("__bitfield%", UnitCount);
            UnitCount += 1;
            Offset := 0;
            while I < T.Members.count
               && T.Members[I].Type.BitfieldBits > 0
               && base_bit_width(T.Members[I].Type.Base) == Width
               && Offset + T.Members[I].Type.BitfieldBits <= Width {
                BM := T.Members[I];
                array_add(*Accessors, .{
                    Field = jai_ident(BM.Name), Storage = Storage, StorageType = storage_type(Width),
                    ValueType = jai_base_type(BM.Type.Base), Offset = Offset, Bits = BM.Type.BitfieldBits,
                });
                Offset += BM.Type.BitfieldBits;
                I += 1;
            }
            print_to_builder(SB, "    %: %;\n", Storage, storage_type(Width));
            continue;
        }
        Default := "";
        if M.Name == "sType" && M.Values.count > 0 {
            SType := first_token(M.Values);
            if table_contains(KnownEnumValues, SType)  Default = tprint(" = .%", SType);
        }
        print_to_builder(SB, "    %: %%;%\n", jai_ident(M.Name), jai_type(M.Type), Default, comment_suffix(M.Comment));
        I += 1;
    }

    if is_pnext_struct(T)  print_to_builder(SB, "    #overlay(sType) _base: %;\n", ifx T.Members[1].Type.IsConst then "VkBaseInStructure" else "VkBaseOutStructure");

    append(SB, "}\n\n");

    for Accessors  emit_bitfield_accessor(SB, T.Name, it);
    if Accessors.count > 0  append(SB, "\n");
}

is_pnext_struct :: (T: vk_type) -> bool {
    if T.Category != .STRUCT return false;
    if T.Name == "VkBaseInStructure" || T.Name == "VkBaseOutStructure" return false;
    if T.Members.count < 2 return false;
    return T.Members[0].Name == "sType" && T.Members[1].Name == "pNext";
}

first_token :: (S: string) -> string {
    I := find_index_from_left(S, #char ",");
    if I == -1 return S;
    return slice(S, 0, I);
}

emit_bitfield_accessor :: (SB: *String_Builder, StructName: string, A: bitfield_accessor) {
    Mask := (cast(u64) 1 << A.Bits) - 1;
    print_to_builder(SB, "get_% :: (s: %) -> % { return cast(%) ((s.% >> %) & %); }\n",
        A.Field, StructName, A.ValueType, A.ValueType, A.Storage, A.Offset, Mask);
    print_to_builder(SB, "set_% :: (s: *%, value: %) { s.% = (s.% & ~cast(%)(% << %)) | ((cast(%) value & %) << %); }\n",
        A.Field, StructName, A.ValueType, A.Storage, A.Storage, A.StorageType, Mask, A.Offset, A.StorageType, Mask, A.Offset);
}

base_bit_width :: (Base: string) -> int {
    T := jai_base_type(Base);
    if T == "u8"  || T == "s8"   return 8;
    if T == "u16" || T == "s16"  return 16;
    if T == "u64" || T == "s64"  return 64;
    return 32;
}

storage_type :: (Width: int) -> string {
    if Width == 8   return "u8";
    if Width == 16  return "u16";
    if Width == 64  return "u64";
    return "u32";
}

emit_alias :: (SB: *String_Builder, T: vk_type) {
    print_to_builder(SB, "% :: %;\n\n", T.Name, T.Alias);
}

command_group :: struct {
    Platform: string;
    Commands: [..]*command;
}

// Buckets required commands by platform guard, unguarded first, preserving registry order.
group_all_commands :: (R: registry) -> [..]command_group {
    Groups: [..]command_group;
    array_add(*Groups, .{});
    for * C: R.Commands  if C.Required  add_to_group(*Groups, C);
    return Groups;
}

// vkGetInstanceProcAddr is resolved from the library by vk_initialize, never through a tier.
group_tier_commands :: (R: registry, Scope: command_scope) -> [..]command_group {
    Groups: [..]command_group;
    array_add(*Groups, .{});
    for * C: R.Commands {
        if !C.Required || C.Scope != Scope continue;
        if C.Name == "vkGetInstanceProcAddr" continue;
        add_to_group(*Groups, C);
    }
    return Groups;
}

add_to_group :: (Groups: *[..]command_group, C: *command) {
    for * G: Groups.* {
        if G.Platform == C.Platform {
            array_add(*G.Commands, C);
            return;
        }
    }
    array_add(Groups, .{ Platform = C.Platform });
    array_add(*Groups.*[Groups.count - 1].Commands, C);
}

free_groups :: (Groups: [..]command_group) {
    for Groups  array_free(it.Commands);
    array_free(Groups);
}

emit_commands :: (SB: *String_Builder, R: registry) {
    Groups := group_all_commands(R);
    defer free_groups(Groups);

    for Groups {
        if it.Commands.count == 0 continue;
        Guarded := it.Platform.count > 0;
        if Guarded  print_to_builder(SB, "#if % {\n", it.Platform);
        for C: it.Commands  emit_command(SB, C, R);
        if Guarded  append(SB, "}\n\n");
    }
}

emit_command :: (SB: *String_Builder, C: *command, R: registry) {
    Pfn := pfn_name(C.Name);
    if !table_contains(*R.TypeIndex, Pfn) {
        print_to_builder(SB, "% :: #type (", Pfn);
        for C.Params {
            if it_index > 0 append(SB, ", ");
            Name := ifx it.Name.count > 0 then jai_ident(it.Name) else tprint("a%", it_index);
            print_to_builder(SB, "%: %", Name, jai_param_type(it.Type));
        }
        print_to_builder(SB, ") -> % #c_call;\n", jai_type(C.ReturnType));
    }
    print_to_builder(SB, "%: %;\n\n", C.Name, Pfn);
}

pfn_name :: (Name: string) -> string {
    return tprint("PFN_%", Name);
}

// Emits one assignment per command of a tier. Fmt takes %1 = indent, %2 = command name.
emit_tier_body :: (SB: *String_Builder, R: registry, Scope: command_scope, Fmt: string) {
    Groups := group_tier_commands(R, Scope);
    defer free_groups(Groups);

    for Groups {
        if it.Commands.count == 0 continue;
        Guarded := it.Platform.count > 0;
        if Guarded  print_to_builder(SB, "    #if % {\n", it.Platform);
        Indent := ifx Guarded then "        " else "    ";
        for C: it.Commands  print_to_builder(SB, Fmt, Indent, C.Name);
        if Guarded  append(SB, "    }\n");
    }
}

emit_loader :: (SB: *String_Builder, R: registry) {
    emit_device_table(SB, R);
    append(SB, LOADER_API);
    emit_tier_loaders(SB, R);
    append(SB, LOADER_PLATFORM);
}

emit_device_table :: (SB: *String_Builder, R: registry) {
    Groups := group_tier_commands(R, .DEVICE);
    defer free_groups(Groups);

    append(SB, "Vk_Device_Table :: struct {\n");
    for Groups {
        if it.Commands.count == 0 continue;
        Guarded := it.Platform.count > 0;
        if Guarded  print_to_builder(SB, "    #if % {\n", it.Platform);
        Indent := ifx Guarded then "        " else "    ";
        for C: it.Commands  print_to_builder(SB, "%1%2: %3;\n", Indent, C.Name, pfn_name(C.Name));
        if Guarded  append(SB, "    }\n");
    }
    append(SB, "}\n\n");
}

emit_tier_loaders :: (SB: *String_Builder, R: registry) {
    append(SB, "load_global_procs :: (load: PFN_vkGetInstanceProcAddr) {\n");
    emit_tier_body(SB, R, .GLOBAL, "%1%2 = xx load(null, \"%2\");\n");
    append(SB, "}\n\n");

    // vkGetDeviceProcAddr is device tier but must be resolved from the instance,
    // otherwise vk_load_device has no loader after vk_load_instance_only.
    append(SB, "load_instance_procs :: (instance: VkInstance, load: PFN_vkGetInstanceProcAddr) {\n");
    append(SB, "    vkGetDeviceProcAddr = xx load(instance, \"vkGetDeviceProcAddr\");\n");
    emit_tier_body(SB, R, .INSTANCE, "%1%2 = xx load(instance, \"%2\");\n");
    append(SB, "}\n\n");

    append(SB, "load_device_procs_from_instance :: (instance: VkInstance, load: PFN_vkGetInstanceProcAddr) {\n");
    emit_tier_body(SB, R, .DEVICE, "%1%2 = xx load(instance, \"%2\");\n");
    append(SB, "}\n\n");

    append(SB, "load_device_procs :: (device: VkDevice, load: PFN_vkGetDeviceProcAddr) {\n");
    emit_tier_body(SB, R, .DEVICE, "%1%2 = xx load(device, \"%2\");\n");
    append(SB, "}\n\n");

    append(SB, "load_device_table :: (table: *Vk_Device_Table, device: VkDevice, load: PFN_vkGetDeviceProcAddr) {\n");
    emit_tier_body(SB, R, .DEVICE, "%1table.%2 = xx load(device, \"%2\");\n");
    append(SB, "}\n\n");

    append(SB, "clear_procs :: () {\n");
    append(SB, "    vkGetInstanceProcAddr = null;\n");
    emit_tier_body(SB, R, .GLOBAL,   "%1%2 = null;\n");
    emit_tier_body(SB, R, .INSTANCE, "%1%2 = null;\n");
    emit_tier_body(SB, R, .DEVICE,   "%1%2 = null;\n");
    append(SB, "}\n\n");
}

LOADER_API :: #string DONE
vk_initialize :: (path := "") -> VkResult {
    if path.count > 0 {
        buf: [1024]u8;
        if path.count >= buf.count return .ERROR_INITIALIZATION_FAILED;
        for 0..path.count - 1  buf[it] = path[it];
        buf[path.count] = 0;
        _vk_lib = open_library(buf.data);
    }
    else {
        for VK_LIB_NAMES {
            _vk_lib = open_library(it.data);
            if _vk_lib break;
        }
    }
    if !_vk_lib return .ERROR_INITIALIZATION_FAILED;

    vkGetInstanceProcAddr = xx library_symbol(_vk_lib, "vkGetInstanceProcAddr");
    if !vkGetInstanceProcAddr {
        close_library(_vk_lib);
        _vk_lib = null;
        return .ERROR_INITIALIZATION_FAILED;
    }

    vk_load_global();
    return .SUCCESS;
}

vk_initialize_custom :: (handler: PFN_vkGetInstanceProcAddr) {
    vkGetInstanceProcAddr = handler;
    vk_load_global();
}

vk_finalize :: () {
    if _vk_lib  close_library(_vk_lib);
    _vk_lib = null;
    _vk_instance = null;
    _vk_device = null;
    clear_procs();
}

vk_get_instance_version :: () -> u32 {
    version: u32 = 1 << 22;
    if vkEnumerateInstanceVersion {
        v: u32;
        if vkEnumerateInstanceVersion(*v) == .SUCCESS  version = v;
    }
    return version;
}

vk_load_global :: (loader: PFN_vkGetInstanceProcAddr = null) {
    load := ifx loader != null then loader else vkGetInstanceProcAddr;
    if !load return;
    load_global_procs(load);
}

vk_load_instance :: (instance: VkInstance, loader: PFN_vkGetInstanceProcAddr = null) {
    load := ifx loader != null then loader else vkGetInstanceProcAddr;
    if !load return;
    _vk_instance = instance;
    load_instance_procs(instance, load);
    load_device_procs_from_instance(instance, load);
}

vk_load_instance_only :: (instance: VkInstance, loader: PFN_vkGetInstanceProcAddr = null) {
    load := ifx loader != null then loader else vkGetInstanceProcAddr;
    if !load return;
    _vk_instance = instance;
    load_instance_procs(instance, load);
}

vk_load_device :: (device: VkDevice, loader: PFN_vkGetDeviceProcAddr = null) {
    load := ifx loader != null then loader else vkGetDeviceProcAddr;
    if !load return;
    _vk_device = device;
    load_device_procs(device, load);
}

vk_load_device_table :: (table: *Vk_Device_Table, device: VkDevice, loader: PFN_vkGetDeviceProcAddr = null) {
    load := ifx loader != null then loader else vkGetDeviceProcAddr;
    if !load return;
    load_device_table(table, device, load);
}

vk_get_loaded_instance :: () -> VkInstance {
    return _vk_instance;
}

vk_get_loaded_device :: () -> VkDevice {
    return _vk_device;
}

#scope_file

_vk_lib: *void;
_vk_instance: VkInstance;
_vk_device: VkDevice;

DONE

LOADER_PLATFORM :: #string DONE
#if OS == .WINDOWS {
    Win :: #import "Windows";

    VK_LIB_NAMES :: string.["vulkan-1.dll"];

    open_library :: (name: *u8) -> *void { return Win.LoadLibraryA(name); }
    library_symbol :: (lib: *void, name: *u8) -> *void { return Win.GetProcAddress(lib, name); }
    close_library :: (lib: *void) { Win.FreeLibrary(lib); }
}
else #if OS == .ANDROID {
    Px :: #import "POSIX";

    VK_LIB_NAMES :: string.["libvulkan.so"];

    open_library :: (name: *u8) -> *void { return Px.dlopen(name, xx (Px.RTLD_NOW | Px.RTLD_LOCAL)); }
    library_symbol :: (lib: *void, name: *u8) -> *void { return Px.dlsym(lib, name); }
    close_library :: (lib: *void) { Px.dlclose(lib); }
}
else #if OS == .LINUX {
    Px :: #import "POSIX";

    VK_LIB_NAMES :: string.["libvulkan.so.1", "libvulkan.so"];

    open_library :: (name: *u8) -> *void { return Px.dlopen(name, xx (Px.RTLD_NOW | Px.RTLD_LOCAL)); }
    library_symbol :: (lib: *void, name: *u8) -> *void { return Px.dlsym(lib, name); }
    close_library :: (lib: *void) { Px.dlclose(lib); }
}
else #if OS == .MACOS || OS == .IOS {
    Px :: #import "POSIX";

    VK_LIB_NAMES :: string.["libvulkan.1.dylib", "libvulkan.dylib", "libMoltenVK.dylib"];

    open_library :: (name: *u8) -> *void { return Px.dlopen(name, xx (Px.RTLD_NOW | Px.RTLD_LOCAL)); }
    library_symbol :: (lib: *void, name: *u8) -> *void { return Px.dlsym(lib, name); }
    close_library :: (lib: *void) { Px.dlclose(lib); }
}
else {
    #assert false "Unsupported OS for the Vulkan loader";
}
DONE

// Emits a `<vkName>Array` wrapper per enumerate command: it runs the two-call
// idiom and returns the result plus an allocated slice.
emit_enumerators :: (SB: *String_Builder, R: registry) {
    for C: R.Commands {
        if !C.Required || !is_enumerator_command(C) continue;

        Elem := element_type(C.Params[C.Params.count - 1].Type);
        IsResult := C.ReturnType.Base == "VkResult";

        print_to_builder(SB, "// Wrapper for `%`: runs the two-call idiom and returns an allocated slice.\n", C.Name);
        print_to_builder(SB, "%Array :: (", C.Name);
        for C.Params {
            if it_index >= C.Params.count - 2 continue;
            if it_index > 0  append(SB, ", ");
            Name := ifx it.Name.count > 0 then jai_ident(it.Name) else tprint("a%", it_index);
            print_to_builder(SB, "%: %", Name, jai_type(it.Type));
        }

        if IsResult {
            print_to_builder(SB, ") -> (VkResult, []%) {\n", Elem);
            print_to_builder(SB, "    count: u32;\n");
            print_to_builder(SB, "    result := %;\n", enumerator_call(C, "null"));
            print_to_builder(SB, "    arr: []%;\n", Elem);
            print_to_builder(SB, "    if result == .SUCCESS {\n");
            print_to_builder(SB, "        arr = NewArray(count, %);\n", Elem);
            print_to_builder(SB, "        result = %;\n", enumerator_call(C, "arr.data"));
            print_to_builder(SB, "    }\n");
            print_to_builder(SB, "    return result, arr;\n");
        }
        else {
            print_to_builder(SB, ") -> []% {\n", Elem);
            print_to_builder(SB, "    count: u32;\n");
            print_to_builder(SB, "    %;\n", enumerator_call(C, "null"));
            print_to_builder(SB, "    arr := NewArray(count, %);\n", Elem);
            print_to_builder(SB, "    %;\n", enumerator_call(C, "arr.data"));
            print_to_builder(SB, "    return arr;\n");
        }
        print_to_builder(SB, "}\n\n");
    }
}

// Builds `vkEnumerateX(passthrough..., *count, <ArrayArg>)` for one of the two calls.
enumerator_call :: (C: command, ArrayArg: string) -> string {
    SB: String_Builder;
    print_to_builder(*SB, "%(", C.Name);
    for C.Params {
        if it_index > 0  append(*SB, ", ");
        if it_index == C.Params.count - 2       append(*SB, "*count");
        else if it_index == C.Params.count - 1  append(*SB, ArrayArg);
        else {
            Name := ifx it.Name.count > 0 then jai_ident(it.Name) else tprint("a%", it_index);
            append(*SB, Name);
        }
    }
    append(*SB, ")");
    return builder_to_string(*SB);
}

// Strips one level of pointer from an output-array parameter to get its element type.
element_type :: (T: c_type) -> string {
    SB: String_Builder;
    for T.ArrayDims  print_to_builder(*SB, "[%]", it);
    for 1..T.PtrDepth - 1  append(*SB, "*");
    append(*SB, jai_base_type(T.Base));
    return builder_to_string(*SB);
}

is_enumerator_command :: (C: command) -> bool {
    if C.Params.count < 2 return false;

    // vkEnumerate* returns (VkResult, slice); a void vkGet* with the same
    // count/array tail returns just the slice.
    IsEnumerate := begins_with(C.Name, "vkEnumerate") && C.ReturnType.Base == "VkResult";
    IsGetVoid   := begins_with(C.Name, "vkGet")       && C.ReturnType.Base == "void" && C.ReturnType.PtrDepth == 0;
    if !IsEnumerate && !IsGetVoid return false;

    CountType := C.Params[C.Params.count - 2].Type;
    ArrayType := C.Params[C.Params.count - 1].Type;

    return
        CountType.Base == "uint32_t" && CountType.PtrDepth > 0 && !CountType.IsConst &&
        ArrayType.Base != "void"     && ArrayType.PtrDepth > 0 && !ArrayType.IsConst;
}

// C array parameters decay to pointers; #c_call rejects fixed-size array arguments.
jai_param_type :: (T: c_type) -> string {
    if T.ArrayDims.count == 0 return jai_type(T);

    SB: String_Builder;
    append(*SB, "*");
    for 1..T.ArrayDims.count - 1  print_to_builder(*SB, "[%]", T.ArrayDims[it]);
    for 1..T.PtrDepth  append(*SB, "*");
    append(*SB, jai_base_type(T.Base));
    return builder_to_string(*SB);
}

jai_type :: (T: c_type) -> string {
    SB: String_Builder;
    for T.ArrayDims  print_to_builder(*SB, "[%]", it);
    for 1..T.PtrDepth  append(*SB, "*");
    append(*SB, jai_base_type(T.Base));
    return builder_to_string(*SB);
}

jai_base_type :: (Name: string) -> string {
    if Name == {
        case "void";     return "void";
        case "char";     return "u8";
        case "int";      return "s32";
        case "float";    return "float32";
        case "double";   return "float64";
        case "size_t";   return "u64";
        case "uint8_t";  return "u8";
        case "uint16_t"; return "u16";
        case "uint32_t"; return "u32";
        case "uint64_t"; return "u64";
        case "int8_t";   return "s8";
        case "int16_t";  return "s16";
        case "int32_t";  return "s32";
        case "int64_t";  return "s64";
    }
    return Name;
}

jai_constant_value :: (EV: enum_value) -> string {
    Raw := EV.RawValue;
    if Raw.count == 0 return "";

    if Raw[0] == #char "\"" return Raw;

    if Raw[0] == #char "(" && Raw[Raw.count - 1] == #char ")" Raw = slice(Raw, 1, Raw.count - 2);

    if begins_with(Raw, "~") {
        Bits: u64 = 0xFFFF_FFFF;
        if contains(Raw, "LL") || contains(Raw, "ll") Bits = 0xFFFF_FFFF_FFFF_FFFF;
        N, Ok := to_integer(trim_right(slice(Raw, 1, Raw.count - 1), "ULul"));
        if !Ok return "";
        return tprint("0x%", formatInt((~cast(u64) N) & Bits, base = 16));
    }

    if contains(Raw, ".") || ends_with_char(Raw, #char "f") || ends_with_char(Raw, #char "F") {
        return trim_right(Raw, "fF");
    }

    Clean := trim_right(Raw, "ULul");
    N, Ok := to_integer(Clean);
    if Ok return Clean;
    return "";
}

ends_with_char :: (S: string, C: u8) -> bool {
    return S.count > 0 && S[S.count - 1] == C;
}

jai_ident :: (Name: string) -> string {
    for JAI_RESERVED  if Name == it  return tprint("%_", Name);
    return Name;
}

PRIMITIVE_C_TYPES :: string.[
    "void", "char", "int", "float", "double", "size_t",
    "uint8_t", "uint16_t", "uint32_t", "uint64_t",
    "int8_t", "int16_t", "int32_t", "int64_t",
];

JAI_RESERVED :: string.[
    "void", "bool", "string", "int", "float", "float32", "float64",
    "s8", "s16", "s32", "s64", "u8", "u16", "u32", "u64",
    "if", "ifx", "else", "then", "for", "while", "break", "continue", "return",
    "struct", "enum", "enum_flags", "union", "using", "defer", "cast", "xx",
    "case", "it", "it_index", "null", "true", "false", "context", "size_of",
];
