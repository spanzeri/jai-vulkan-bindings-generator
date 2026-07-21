/*
Vulkan bindings/loader generator for the JAI programming language.
Based on the Khronos registry (vk.xml) rather than the vulkan headers.
For license informations, see the accompanying LICENSE.txt file.
*/

main :: () {
    XmlRoot, XmlOk := xml_parse_file("vk.xml");
    if !XmlOk {
        exit(-1);
    }
    log(" > XML parsed succesfully;");

    Registry, RegistryOk := make_registry_from_xml(XmlRoot);
    if !RegistryOk {
        log_error("Failed to create registry from the parsed XML");
        exit(-2);
    }
    log(" > Registry initialised from XML content;");

    Global, Instance, Device := count_command_scopes(Registry);
    log(" > Commands: % global, % instance, % device;", Global, Instance, Device);

    Output := emit_registry(Registry);
    if !write_entire_file("vulkan.jai", Output) {
        log_error("Failed to write generated bindings");
        exit(-3);
    }
    log(" > Wrote vulkan.jai (% bytes);", Output.count);
}

#load "xml.jai";
#load "registry.jai";
#load "emitter.jai";

#import "Basic";
#import "File";
#import "Sort";

#run {
    #import "Compiler";

    OUT_PATH :: "bin";

    BuildOpts := Build_Options_During_Compile.{};
    BuildOpts.output_path = OUT_PATH;
    BuildOpts.output_executable_name = "generator";
    make_directory_if_it_does_not_exist(OUT_PATH);

    set_build_options_dc(BuildOpts);
}

