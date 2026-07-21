/*
 * Simple XML parser for: JAI vulkan binding generator.
 * For license information, see the accompanying: LICENSE.txt file.
 */
 
#import "File";
#import "String";

xml_attribute :: struct {
    Name: string;
    Value: string;
}

xml_node :: struct {
    Tag: string;
    Text: string;
    Attrs: [..]xml_attribute;
    Children: [..]xml_node;
}

xml_is_text :: (Node: xml_node) -> bool {
    return Node.Tag.count == 0;
}

xml_parse_file :: (Path: string) -> (Root: xml_node, Ok: bool) {
    Content, ReadOk := read_entire_file(Path);
    if !ReadOk {
        log_error("Failed to read file: %", Path);
        return {}, false;
    }

    P := parser.{ Path = Path, Src = Content };
    skip_prologue(*P);
    if P.Failed {
        return {}, false;
    }

    skip_whitespaces(*P);
    if at_end(*P) {
        parse_error(*P, "XML file is empty");
        return {}, false;
    }

    Root := parse_node(*P);
    if P.Failed {
        return {}, false;
    }

    return Root, true;
}

xml_get_attribute :: (Node: xml_node, Name: string) -> (Value: string, Found: bool) {
    if xml_is_text(Node) return "", false;
    for Node.Attrs {
        if it.Name == Name {
            return it.Value, true;
        }
    }
    return "", false;
}

xml_get_attribute :: (Node: xml_node, Name: string, Default: string) -> string {
    Attr, Found := xml_get_attribute(Node, Name);
    if !Found return Default;
    return Attr;
}

xml_get_first_children :: (Node: xml_node, TagName: string) -> (Child: xml_node, Found: bool) {
    if xml_is_text(Node) return .{}, false;
    for Node.Children {
        if it.Tag == TagName {
            return it, true;
        }
    }
    return .{}, false;
}

xml_get_children :: (Node: xml_node, TagName: string) -> [..]*xml_node {
    Children: [..]*xml_node;
    for * Node.Children {
        if it.Tag == TagName {
            array_add(*Children, it);
        }
    }
    return Children;
}

xml_get_inner_text :: (Node: xml_node) -> string {
    SB: String_Builder;
    for Node.Children if xml_is_text(it) append(*SB, it.Text);
    return builder_to_string(*SB);
}

xml_get_children_content :: (Node: xml_node, Name: string) -> string, bool {
    Result := "";
    Child, Found := xml_get_first_children(Node, Name);
    HasAnyText := false;
    SB: String_Builder;
    if Found && !xml_is_text(Child) {
        for Child.Children {
            if xml_is_text(it) {
                HasAnyText = true;
                append(*SB, it.Text);
            }
        }
    }
    if HasAnyText {
        return builder_to_string(*SB), true;
    }
    return "", false;
}

xml_get_children_content :: (Node: xml_node, Name: string, DefaultValue: string) -> string {
    Content, Found := xml_get_children_content(Node, Name);
    if Found return Content;
    return DefaultValue;
}

#scope_file

parser :: struct {
    Path: string;
    Src: string;
    Cursor: s64;
    Line: s32 = 1;
    Failed: bool;
}

at_end :: (using P: *parser) -> bool {
    return Cursor == Src.count;
}

peek :: (using P: *parser) -> u8 {
    if Cursor == Src.count return 0;
    return Src[Cursor];
}

eat :: (using P: *parser, Count := 1) {
    if Cursor + Count >= Src.count {
        Cursor = Src.count;
    }
    for 0 .. Count - 1 {
        if Src[Cursor] == "\n" Line += 1;
        Cursor += 1;
    }
}

starts_with :: (using P: *parser, S: string) -> bool {
    if Cursor + S.count > Src.count return false;
    return slice(Src, Cursor, S.count) == S;
}

match :: (using P: *parser, S: string) -> bool {
    if starts_with(P, S) {
        eat(P, S.count);
        return true;
    }
    return false;
}

skip_whitespaces :: (using P: *parser) {
    while !at_end(P) && is_space(peek(P)) eat(P);
}

expect :: (using P: *parser, C: u8) {
     if peek(P) != C {
         parse_error(P, "Expected '%', found '%'", string.{1, *C}, string.{1, *peek(P)});
     }
     eat(P);
}

parse_error :: (using P: *parser, Format: string, Args: ..Any) {
    log_error("%:%: Error: XML parser: %", Path, Line, tprint(Format, ..Args));
    Failed = true;
}

skip_prologue :: (using P: *parser) {
    skip_whitespaces(P);
    if starts_with(P, "<?") {
        if !skip_until_after(P, "?>") {
            parse_error(P, "Unterminated prologue");
        }
    }
}

skip_until_after :: (using P: *parser, S: string) -> bool {
    if S.count == 0 { return true; }
    while !at_end(P) {
        if match(P, S) { return true; }
        eat(P);
    }
    return false;
}

parse_node :: (using P: *parser) -> xml_node {
    Node := xml_node.{};

    skip_whitespaces(P);
    if match(P, "<") {
        // We are parsing a tag
        Node.Tag = parse_identifier(P);

        while true {
            skip_whitespaces(P);
            if at_end(P) {
                parse_error(P, "Unterminated tag: %", Node.Tag);
                return .{};
            }
            if match(P, "/>") {
                return Node;
            }

            if match(P, ">") break;

            Attribute := parse_attribute(P);
            if Failed return .{};

            array_add(*Node.Attrs, Attribute);
        }

        while true {
            skip_whitespaces(P);
            if match(P, "</") {
                if !match(P, Node.Tag) {
                    parse_error(P, "Mismatched tag termination. Expected: %, Found: %", Node.Tag, parse_identifier(P));
                    return .{};
                }
                skip_whitespaces(P);
                expect(P, ">");
                break;
            }

            Child := parse_node(P);
            if Failed {
                return .{};
            }
            array_add(*Node.Children, Child);
        }
    }
    else {
        // We are parsing text
        StringBuilder := String_Builder.{};
        LastWasSpace := false;
        while !at_end(P) && !Failed && !starts_with(P, "<") {
            if match(P, "&gt;") {
                append(*StringBuilder, ">");
            }
            else if match(P, "&lt;") {
                append(*StringBuilder, "<");
            }
            else if match(P, "&amp;") {
                append(*StringBuilder, "&");
            }
            else if match(P, "&quot;") {
                append(*StringBuilder, "\"");
            }
            else if match(P, "&nbsp;") {
                append(*StringBuilder, " ");
            }
            else if match(P, "&nbsp;") {
                append(*StringBuilder, " ");
            }
            else {
                C := peek(P);
                if C == " " {
                    if !LastWasSpace {
                        append(*StringBuilder, " ");
                    }
                    LastWasSpace = true;
                }
                else {
                    LastWasSpace = false;
                    append(*StringBuilder, C);
                }
                eat(P);
            }
        }

        Node.Text = builder_to_string(*StringBuilder);
    }

    return Node;
}

parse_identifier :: (using P: *parser) -> string {
    if !is_alnum(peek(P)) {
        C := peek(P);
        parse_error(P, "Expected a identifier. Got '%'", string.{1, *C});
        return {};
    }

    Start := Src.data + Cursor;
    C := peek(P);
    while is_alnum(C) || C == "_" {
        eat(P);
        C = peek(P);
    }

    End := Src.data + Cursor;
    return copy_string(.{ End - Start, Start });
}

parse_attribute :: (using P: *parser) -> xml_attribute {
    skip_whitespaces(P);

    name := parse_identifier(P);
    if Failed return .{};

    skip_whitespaces(P);
    expect(P, "=");
    if Failed return .{};
    skip_whitespaces(P);

    value := parse_string(P);
    if Failed return .{};

    return .{ name, value };
}

parse_string :: (using P: *parser) -> string {
    if !match(P, "\"") return "";
    sb: String_Builder;
    while !at_end(P) {
        if match(P, "\"") {
            return builder_to_string(*sb);
        }

        if match(P, "&quot;") {
            append(*sb, "\"");
        }
        else if match(P, "&amp;") {
            append(*sb, "&");
        }
        else if match(P, "&lt;") {
            append(*sb, "<");
        }
        else if match(P, "&gt;") {
            append(*sb, ">");
        }
        else if match(P, "&apos;") {
            append(*sb, "'");
        }
        else if match(P, "\\\\") {
            append(*sb, "\\");
        }
        else if match(P, "\\\"") {
            append(*sb, "\\");
        }
        else if match(P, "\\t") {
            append(*sb, "\t");
        }
        else if match(P, "\\r\\n") {
            append(*sb, "\n");
        }
        else if match(P, "\\n") {
            append(*sb, "\n");
        }
        else {
            append(*sb, peek(P));
            eat(P);
        }
    }

    parse_error(P, "Unterminated string");
    return "";
}


