/*
 * Vulkan registry data for: JAI vulkan binding generator.
 * For license information, see the accompanying: LICENSE.txt file.
 */

registry :: struct {
    Types:        [..]vk_type;
    Enums:        [..]vk_enum;
    Commands:     [..]command;
    Constants:    [..]enum_value;

    //            maps
    TypeIndex:    Table(string, int);
    EnumIndex:    Table(string, int);
    CommandIndex: Table(string, int);
    SeenEnumName: Table(string, bool);

    Platforms:    Table(string, string);
    VendorTags:   [..]string;

    Copyright:    string;
}

vk_type :: struct {
    Name:         string;
    Category:     type_category;
    Alias:        string;
    Api:          string;
    Platform:     string;
    Requires:     string;
    Comment:      string;
    Required:     bool;

    // handle information
    Dispatchable: bool;
    HandleParent: string;
    ObjectType: string;

    // basetype
    BaseType:     string;

    // bitmask
    FlagBits:     string;
    Flag64:       bool;

    // struct/union
    Members:      [..]member;

    // func   pointers
    ReturnType:   c_type;
}

type_category :: enum {
    NONE;
    INCLUDE;
    DEFINE;
    BASETYPE;
    HANDLE;
    ENUM;
    FUNCPOINTER;
    STRUCT;
    UNION;
    BITMASK;
    ALIAS;
}

c_type :: struct {
    Base:         string;
    PtrDepth:     s32;
    IsConst:      bool;
    IsConstPtr:   bool;
    ArrayDims:    [..]string;
    BitfieldBits: s32;
    Comment:      string;
}

member :: struct  {
    Name:     string;
    Type:     c_type;
    Values:   string;
    Optional: bool;
    Len:      string;
    Api:      string;
    Comment:  string;
}

vk_enum :: struct {
    Name:      string;
    IsBitmask: bool;
    Bitwidth:  s32;
    Values:    [..]enum_value;
}

enum_value :: struct {
    Name:     string;
    Value:    s64;
    Alias:    string;
    IsU64:    bool;
    IsBitpos: bool;
    RawValue: string;
    Comment:  string;
}

command_scope :: enum {
    GLOBAL;
    INSTANCE;
    DEVICE;
};

command :: struct {
    Name: string;
    Alias: string;
    ReturnType: c_type;
    Params: [..]member;
    Api: string;
    Scope: command_scope;
    Platform: string;
    Required: bool;
}

#import "Hash_Table";

make_registry_from_xml :: (Root: xml_node) -> (registry, bool) {
    Registry: registry;

    CopyrightNode, HasCopyright := xml_get_first_children(Root, "comment");
    if HasCopyright Registry.Copyright = xml_get_inner_text(CopyrightNode);

    PlatNode, PlatFound := xml_get_first_children(Root, "platforms");
    if !PlatFound {
        log_error("Failed to find platforms node in the xml");
        return Registry, false;
    }
    process_platforms(PlatNode, *Registry);

    TagsNode, TagsFound := xml_get_first_children(Root, "tags");
    if !TagsFound {
        log_error("Failed to find tags node in the xml");
        return Registry, false;
    }
    process_tags(TagsNode, *Registry);

    TypesNode, TypesFound := xml_get_first_children(Root, "types");
    if !TypesFound {
        log_error("Failed to find types node in the xml");
        return Registry, false;
    }
    process_types(TypesNode, *Registry);

    process_enums(Root, *Registry);

    CmdNode, CmdFound := xml_get_first_children(Root, "commands");
    if !CmdFound {
        log_error("Failed to find commands node in the xml");
        return Registry, false;
    }
    process_commands(CmdNode, *Registry);

    process_features_extensions(Root, *Registry);

    resolve_aliases(*Registry);

    classify_command_scopes(*Registry);

    return Registry, true;
}

count_command_scopes :: (R: registry) -> (Global: int, Instance: int, Device: int) {
    Global, Instance, Device := 0;
    for R.Commands {
        if !it.Required continue;
        if it.Scope == {
            case .GLOBAL;   Global   += 1;
            case .INSTANCE; Instance += 1;
            case .DEVICE;   Device   += 1;
        }
    }
    return Global, Instance, Device;
}

#scope_file

MAX_ALIAS_DEPTH :: 16;

resolve_aliases :: (R: *registry) {
    resolve_command_aliases(R);
    resolve_enum_aliases(R);
    validate_type_aliases(R);
}

resolve_command_aliases :: (R: *registry) {
    for * C: R.Commands {
        if C.Alias.count == 0 continue;
        Target := resolve_command(R, C.Alias);
        if !Target {
            log_error("Command alias '%' targets unresolved command '%'", C.Name, C.Alias);
            continue;
        }
        C.ReturnType = Target.ReturnType;
        C.Params     = Target.Params;
        C.Scope      = Target.Scope;
        C.Api        = Target.Api;
    }
}

resolve_command :: (R: *registry, Name: string) -> *command {
    Cur := Name;
    for 1..MAX_ALIAS_DEPTH {
        Found, Idx := table_find(*R.CommandIndex, Cur);
        if !Found return null;
        C := *R.Commands[Idx];
        if C.Alias.count == 0 return C;
        Cur = C.Alias;
    }
    return null;
}

resolve_enum_aliases :: (R: *registry) {
    ByName: Table(string, *enum_value);
    defer deinit(*ByName);
    for * E: R.Enums     for * V: E.Values  table_set(*ByName, V.Name, V);
    for * C: R.Constants                    table_set(*ByName, C.Name, C);

    for * E: R.Enums {
        for * V: E.Values {
            if V.Alias.count == 0 continue;
            Target := resolve_enum_value(*ByName, V.Alias);
            if !Target {
                log_error("Enum value alias '%' targets unresolved value '%'", V.Name, V.Alias);
                continue;
            }
            V.Value    = Target.Value;
            V.IsU64    = Target.IsU64;
            V.IsBitpos = Target.IsBitpos;
        }
    }

    for * C: R.Constants {
        if C.Alias.count == 0 continue;
        Target := resolve_enum_value(*ByName, C.Alias);
        if !Target {
            log_error("Constant alias '%' targets unresolved value '%'", C.Name, C.Alias);
            continue;
        }
        C.Value    = Target.Value;
        C.RawValue = Target.RawValue;
    }
}

resolve_enum_value :: (ByName: *Table(string, *enum_value), Name: string) -> *enum_value {
    Cur := Name;
    for 1..MAX_ALIAS_DEPTH {
        Found, V := table_find(ByName, Cur);
        if !Found return null;
        if V.Alias.count == 0 return V;
        Cur = V.Alias;
    }
    return null;
}

validate_type_aliases :: (R: *registry) {
    for * T: R.Types {
        if T.Category != .ALIAS continue;
        if !resolve_type(R, T.Alias) {
            log_error("Type alias '%' targets unresolved type '%'", T.Name, T.Alias);
        }
    }
}

resolve_type :: (R: *registry, Name: string) -> *vk_type {
    Cur := Name;
    for 1..MAX_ALIAS_DEPTH {
        Found, Idx := table_find(*R.TypeIndex, Cur);
        if !Found return null;
        T := *R.Types[Idx];
        if T.Category != .ALIAS return T;
        Cur = T.Alias;
    }
    return null;
}

process_platforms :: (PlatNode: xml_node, R: *registry) {
    Nodes := xml_get_children(PlatNode, "platform");
    defer array_free(Nodes);

    for Nodes {
        Name, NameFound := xml_get_attribute(it, "name");
        if !NameFound {
            log_error("Name not found for a platform, it will be skipped");
            continue;
        }
        Protect, ProtectFound := xml_get_attribute(it, "protect");
        if !ProtectFound {
            log_error("Protect not found for platform '%', it will be skipped", Name);
            continue;
        }
        table_add(*R.Platforms, Name, Protect);
    }
}

process_tags :: (TagsNode: xml_node, R: *registry) {
    Nodes := xml_get_children(TagsNode, "tag");
    defer array_free(Nodes);

    for Nodes {
        Name, NameFound := xml_get_attribute(it, "name");
        if !NameFound {
            log_error("Name not found for a tag, it will be skipped");
            continue;
        }
        array_add(*R.VendorTags, Name);
    }
}

process_types :: (Types: xml_node, R: *registry) {
    Nodes := xml_get_children(Types, "type");
    defer array_free(Nodes);

    for Nodes {
        if !is_api_compatible(it) continue;

        Category := xml_get_attribute(it, "category", "");
        Alias, IsAlias := xml_get_attribute(it, "alias");
        Comment := xml_get_attribute(it, "comment");

        if IsAlias {
            Name := xml_get_attribute(it, "name");
            assert(Name.count > 0, "alias <type> for '%' missing name", Alias);
            push_type(make_type_alias(Name, Alias, Comment), R);
            continue;
        }

        if Category == {
            case "basetype";
                Name, NameFound := xml_get_children_content(it, "name");
                assert(NameFound, "basetype <type> missing <name> child");
                BaseType := xml_get_children_content(it, "type", "");
                push_type(make_type_basetype(Name, BaseType, Comment), R);

            case "bitmask";
                Name, NameFound := xml_get_children_content(it, "name");
                assert(NameFound, "bitmask <type> missing <name> child");
                Requires := xml_get_attribute(it, "requires", "");
                BitValues := xml_get_attribute(it, "bitvalues", "");
                FlagBits := ifx Requires.count > 0 then Requires else BitValues;
                Type := xml_get_children_content(it, "type", "");
                Flag64 := (BitValues.count > 0) || (Type == "VkFlags64");
                push_type(make_type_bitmask(Name, FlagBits, Flag64, Comment), R);

            case "enum";
                Name, NameFound := xml_get_attribute(it, "name");
                assert(NameFound, "enum <type> missing name attribute");
                push_type(make_type_enum(Name, Comment), R);

            case "handle";
                Name, NameFound := xml_get_children_content(it, "name");
                assert(NameFound, "handle <type> missing <name> child");
                Parent := xml_get_attribute(it, "parent", "");
                ObjectTypeEnum := xml_get_attribute(it, "objtypeenum", "");
                Type := xml_get_children_content(it, "type", "");
                IsDispatchable := (Type != "VK_DEFINE_NON_DISPATCHABLE_HANDLE");

                push_type(make_type_handle(Name, Parent, ObjectTypeEnum, IsDispatchable, Comment), R);

            case "struct"; #through;
            case "union";
                Name := xml_get_attribute(it, "name", "");
                assert(Name.count > 0);
                Cat := ifx Category == "union" then type_category.UNION else type_category.STRUCT;
                T := make_type_struct(Name, Cat, Comment);
                Members := xml_get_children(it, "member");
                defer array_free(Members);
                for M: Members {
                    if !is_api_compatible(M) continue;
                    array_add(*T.Members, parse_member(M));
                }
                push_type(T, R);

            case "funcpointer";
                Proto, HasProto := xml_get_first_children(it, "proto");
                if !HasProto continue;
                RetType, Name := parse_c_decl(Proto);
                assert(Name.count > 0);
                T := make_type_funcpointer(Name, RetType, Comment);
                Params := xml_get_children(it, "param");
                defer array_free(Params);
                for P: Params {
                    if !is_api_compatible(P) continue;
                    array_add(*T.Members, parse_member(P));
                }
                push_type(T, R);

            case "include"; case "define";
                // Skipped: includes are C headers; defines are hand-written in the emit prelude.

            case "";

            case;
                assert(false, "Unhandled <type> category: '%'", Category);
        }
    }
}

parse_member :: (Node: xml_node) -> member {
    M: member;
    M.Type, M.Name = parse_c_decl(Node);
    M.Optional = xml_get_attribute(Node, "optional", "") == "true";
    M.Len      = xml_get_attribute(Node, "len", "");
    M.Values   = xml_get_attribute(Node, "values", "");
    M.Api      = xml_get_attribute(Node, "api", "");
    M.Comment  = xml_get_attribute(Node, "comment", "");
    return M;
}

parse_c_decl :: (Decl: xml_node) -> (Type: c_type, Name: string) {
    Type: c_type;
    Name: string;
    HasSeenType := false;
    HasSeenName := false;

    for Decl.Children {
        if it.Tag == {
            case "type";
                Type.Base = xml_get_inner_text(it);
                HasSeenType = true;
            case "name";
                Name = xml_get_inner_text(it);
                HasSeenName = true;
            case "enum";
                array_add(*Type.ArrayDims, xml_get_inner_text(it));
            case "comment";
                Type.Comment = xml_get_inner_text(it);
            case "";
                Text := it.Text;
                if !HasSeenType {
                    if contains(Text, "const") Type.IsConst = true;
                }
                else if !HasSeenName {
                    for C: cast([]u8) Text if C == "*" Type.PtrDepth += 1;
                    if contains(Text, "const") Type.IsConstPtr = true;
                }
                else {
                    parse_decl_suffix(Text, *Type);
                }
            case;
        }
    }
    return Type, Name;
}

parse_decl_suffix :: (Text: string, Type: *c_type) {
    Colon := find_index_from_left(Text, #char ":");
    if Colon != -1 {
        Bits, Ok := to_integer(slice(Text, Colon + 1, Text.count - Colon - 1));
        if Ok Type.BitfieldBits = xx Bits;
    }
    else {
        I := 0;
        while I < Text.count {
            if Text[I] == "[" {
                J := I + 1;
                while J < Text.count && Text[J] != "]" J += 1;
                Dim := slice(Text, I + 1, J - I - 1);
                if Dim.count > 0 array_add(*Type.ArrayDims, Dim);
                I = J + 1;
            }
            else I += 1;
        }
    }
}

process_enums :: (Root: xml_node, R: *registry) {
    Nodes := xml_get_children(Root, "enums");
    defer array_free(Nodes);

    for Nodes {
        Name := xml_get_attribute(it, "name", "");
        if Name.count == 0 continue;
        Type := xml_get_attribute(it, "type", "");

        Values := xml_get_children(it, "enum");
        defer array_free(Values);

        if Type == "constants" {
            for V: Values {
                if !is_api_compatible(V) continue;
                EV, Ok := parse_enum_value(V, false);
                if Ok array_add(*R.Constants, EV);
            }
            continue;
        }

        E: vk_enum;
        E.Name      = Name;
        E.IsBitmask = Type == "bitmask";
        E.Bitwidth  = xx ifx xml_get_attribute(it, "bitwidth", "") == "64" then 64 else 32;

        for V: Values {
            if !is_api_compatible(V) continue;
            EV, Ok := parse_enum_value(V, E.Bitwidth == 64);
            if Ok array_add(*E.Values, EV);
        }
        push_enum(E, R);
    }
}

parse_enum_value :: (Node: xml_node, U64: bool) -> (enum_value, bool) {
    EV: enum_value;
    EV.Name = xml_get_attribute(Node, "name", "");
    if EV.Name.count == 0 {
        log_error("<enum> in a group is missing its name attribute");
        return EV, false;
    }
    EV.Comment = xml_get_attribute(Node, "comment", "");

    Alias, IsAlias := xml_get_attribute(Node, "alias");
    if IsAlias {
        EV.Alias = Alias;
        return EV, true;
    }

    EV.IsU64 = U64;

    Bitpos, HasBitpos := xml_get_attribute(Node, "bitpos");
    if HasBitpos {
        Pos, Ok := to_integer(Bitpos);
        if !Ok {
            log_error("enum '%' has an unparseable bitpos '%'", EV.Name, Bitpos);
            return EV, false;
        }
        EV.IsBitpos = true;
        EV.RawValue = Bitpos;
        EV.Value    = (cast(s64) 1) << Pos;
        return EV, true;
    }

    Value, HasValue := xml_get_attribute(Node, "value");
    if HasValue {
        EV.RawValue = Value;
        N, Ok := parse_c_int(Value);
        if Ok EV.Value = N;
        return EV, true;
    }

    log_error("enum '%' has no value, bitpos, or alias", EV.Name);
    return EV, false;
}

parse_c_int :: (S: string) -> (s64, bool) {
    if begins_with(S, "0x") || begins_with(S, "0X") {
        V, Ok := string_to_int(slice(S, 2, S.count - 2), 16, s64);
        return V, Ok;
    }
    V, Ok := to_integer(S);
    return V, Ok;
}

push_enum :: (E: vk_enum, R: *registry) {
    array_add(*R.Enums, E);
    table_add(*R.EnumIndex, E.Name, R.Enums.count - 1);
}

process_features_extensions :: (Root: xml_node, R: *registry) {
    Feats := xml_get_children(Root, "feature");
    defer array_free(Feats);
    for Feats {
        if !is_api_compatible(it) continue;
        process_require_block(it, "", "", R);
    }

    ExtsNode, Found := xml_get_first_children(Root, "extensions");
    if !Found return;
    Exts := xml_get_children(ExtsNode, "extension");
    defer array_free(Exts);

    for Exts {
        if !is_ext_supported(it) continue;
        if xml_get_attribute(it, "platform", "").count > 0 continue;
        process_require_block(it, xml_get_attribute(it, "number", ""), "", R);
    }

    for Exts {
        if !is_ext_supported(it) continue;
        Plat := xml_get_attribute(it, "platform", "");
        if Plat.count == 0 continue;
        Protect := "";
        PFound, PVal := table_find(*R.Platforms, Plat);
        if PFound Protect = PVal;
        process_require_block(it, xml_get_attribute(it, "number", ""), Protect, R);
    }
}

process_require_block :: (Container: xml_node, ExtNumber: string, Platform: string, R: *registry) {
    Requires := xml_get_children(Container, "require");
    defer array_free(Requires);

    for Requires {
        if !is_api_compatible(it) continue;
        for Child: it.Children {
            if Child.Tag == {
                case "enum";    inject_enum(Child, ExtNumber, R);
                case "type";    mark_type_required(Child, Platform, R);
                case "command"; mark_command_required(Child, Platform, R);
            }
        }
    }
}

inject_enum :: (Node: xml_node, ExtNumber: string, R: *registry) {
    if !is_api_compatible(Node) return;
    Name := xml_get_attribute(Node, "name", "");
    if Name.count == 0 return;

    Extends := xml_get_attribute(Node, "extends", "");
    if Extends.count == 0 {
        Value, HasValue := xml_get_attribute(Node, "value");
        if !HasValue return;
        EV: enum_value;
        EV.Name     = Name;
        EV.RawValue = Value;
        EV.Comment  = xml_get_attribute(Node, "comment", "");
        N, Ok := parse_c_int(Value);
        if Ok EV.Value = N;
        array_add(*R.Constants, EV);
        return;
    }

    Found, Idx := table_find(*R.EnumIndex, Extends);
    if !Found {
        log_error("enum '%' extends unknown enum group '%'", Name, Extends);
        return;
    }
    E := *R.Enums[Idx];

    EV: enum_value;
    EV.Name    = Name;
    EV.Comment = xml_get_attribute(Node, "comment", "");

    Alias, IsAlias := xml_get_attribute(Node, "alias");
    if IsAlias {
        EV.Alias = Alias;
        array_add(*E.Values, EV);
        return;
    }

    Bitpos, HasBitpos := xml_get_attribute(Node, "bitpos");
    if HasBitpos {
        Pos, Ok := to_integer(Bitpos);
        if !Ok return;
        EV.IsBitpos = true;
        EV.IsU64    = E.Bitwidth == 64;
        EV.RawValue = Bitpos;
        EV.Value    = (cast(s64) 1) << Pos;
        array_add(*E.Values, EV);
        return;
    }

    Offset, HasOffset := xml_get_attribute(Node, "offset");
    if HasOffset {
        Off, OkO := to_integer(Offset);
        ExtNum, OkE := to_integer(xml_get_attribute(Node, "extnumber", ExtNumber));
        if !OkO || !OkE {
            log_error("enum '%' extends '%' with unparseable offset/extnumber", Name, Extends);
            return;
        }
        V := 1_000_000_000 + (ExtNum - 1) * 1000 + Off;
        if xml_get_attribute(Node, "dir", "") == "-" V = -V;
        EV.Value = V;
        array_add(*E.Values, EV);
        return;
    }

    Value, HasValue := xml_get_attribute(Node, "value");
    if HasValue {
        EV.RawValue = Value;
        N, Ok := parse_c_int(Value);
        if Ok EV.Value = N;
        array_add(*E.Values, EV);
    }
}

mark_type_required :: (Node: xml_node, Platform: string, R: *registry) {
    Name := xml_get_attribute(Node, "name", "");
    if Name.count == 0 return;
    Found, Idx := table_find(*R.TypeIndex, Name);
    if !Found return;
    T := *R.Types[Idx];
    if !T.Required && Platform.count > 0 T.Platform = Platform;
    T.Required = true;
}

mark_command_required :: (Node: xml_node, Platform: string, R: *registry) {
    Name := xml_get_attribute(Node, "name", "");
    if Name.count == 0 return;
    Found, Idx := table_find(*R.CommandIndex, Name);
    if !Found return;
    C := *R.Commands[Idx];
    if !C.Required && Platform.count > 0 C.Platform = Platform;
    C.Required = true;
}

is_ext_supported :: (Node: xml_node) -> bool {
    Sup := xml_get_attribute(Node, "supported", "");
    if Sup.count == 0 return false;
    for Token: split(Sup, #char ",") if Token == "vulkan" return true;
    return false;
}

process_commands :: (Commands: xml_node, R: *registry) {
    Nodes := xml_get_children(Commands, "command");
    defer array_free(Nodes);

    for Nodes {
        Alias, IsAlias := xml_get_attribute(it, "alias");
        if IsAlias {
            Name := xml_get_attribute(it, "name", "");
            if Name.count > 0 push_command(.{ Name = Name, Alias = Alias }, R);
            continue;
        }

        if !is_api_compatible(it) continue;

        Proto, HasProto := xml_get_first_children(it, "proto");
        if !HasProto continue;

        C: command;
        C.ReturnType, C.Name = parse_c_decl(Proto);
        if C.Name.count == 0 continue;
        C.Api = xml_get_attribute(it, "api", "");

        Params := xml_get_children(it, "param");
        defer array_free(Params);
        for P: Params {
            if !is_api_compatible(P) continue;
            array_add(*C.Params, parse_member(P));
        }
        push_command(C, R);
    }
}

// Runs after alias resolution so aliases classify from their target's params.
classify_command_scopes :: (R: *registry) {
    for * C: R.Commands  C.Scope = classify_command_scope(C, R);
}

classify_command_scope :: (C: *command, R: *registry) -> command_scope {
    if C.Name == {
        case "vkGetInstanceProcAddr"; #through;
        case "vkCreateInstance"; #through;
        case "vkEnumerateInstanceVersion"; #through;
        case "vkEnumerateInstanceExtensionProperties"; #through;
        case "vkEnumerateInstanceLayerProperties";
            return .GLOBAL;
    }
    if C.Params.count == 0 return .INSTANCE;

    Handle := C.Params[0].Type.Base;
    if Handle == "VkDevice" || Handle == "VkQueue" || Handle == "VkCommandBuffer" {
        return .DEVICE;
    }

    for 1..MAX_ALIAS_DEPTH {
        if Handle.count == 0 break;
        Found, Idx := table_find(*R.TypeIndex, Handle);
        if !Found break;
        Parent := R.Types[Idx].HandleParent;
        if Parent == "VkDevice" return .DEVICE;
        Handle = Parent;
    }
    return .INSTANCE;
}

push_command :: (C: command, R: *registry) {
    array_add(*R.Commands, C);
    table_add(*R.CommandIndex, C.Name, R.Commands.count - 1);
}

make_type_alias :: (Name: string, Alias: string, Comment: string) -> vk_type {
    return .{
        Name     = Name,
        Category = .ALIAS,
        Comment  = Comment,
        Alias    = Alias,
    };
}

make_type_handle :: (
    Name: string,
    ParentHandle: string,
    ObjectType: string,
    Dispatchable: bool,
    Comment: string
) -> vk_type {
    return .{
        Name         = Name,
        Category     = .HANDLE,
        Comment      = Comment,
        HandleParent = ParentHandle,
        ObjectType   = ObjectType,
        Dispatchable = Dispatchable,
    };
}

make_type_basetype :: (Name: string, BaseType: string, Comment: string) -> vk_type {
    return .{
        Name     = Name,
        Category = .BASETYPE,
        Comment  = Comment,
        BaseType = BaseType,
    };
}

make_type_bitmask :: (Name: string, FlagBits: string, Flag64: bool, Comment: string) -> vk_type {
    return .{
        Name     = Name,
        Category = .BITMASK,
        Comment  = Comment,
        FlagBits = FlagBits,
        Flag64   = Flag64,
    };
}

make_type_enum :: (Name: string, Comment: string) -> vk_type {
    return .{
        Name     = Name,
        Category = .ENUM,
        Comment  = Comment,
    };
}

make_type_struct :: (Name: string, Category: type_category, Comment: string) -> vk_type {
    return .{ Name = Name, Category = Category, Comment = Comment };
}

make_type_funcpointer :: (Name: string, ReturnType: c_type, Comment: string) -> vk_type {
    return .{ Name = Name, Category = .FUNCPOINTER, Comment = Comment, ReturnType = ReturnType };
}

push_type :: (Type: vk_type, R: *registry) {
    array_add(*R.Types, Type);
    table_add(*R.TypeIndex, Type.Name, R.Types.count - 1);
}

is_api_compatible :: (Node: xml_node) -> bool {
    Api := xml_get_attribute(Node, "api", "");
    if Api.count == 0 return true;
    for Token : split(Api, #char ",") {
        if Token == "vulkan" return true;
    }
    return false;
}

