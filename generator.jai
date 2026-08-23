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
    if !write_entire_file("Vulkan.jai", Output) {
        log_error("Failed to write generated bindings");
        exit(-3);
    }
    log(" > Wrote Vulkan.jai (% bytes);", Output.count);

    log(" > Generate VMA bindings");
    // Android is a cross-target: opt in with "generator -android". The bindings are
    // identical for both ABIs, so we generate once and just build the second library.
    if array_find(get_command_line_arguments(), "-android") {
        Ok := generate_vma_bindings(.ANDROID, .ARM64);
        Ok &&= build_vma_libraries(.ANDROID, .X64);
        if !Ok  log_error(" ! ERROR: Android VMA generation failed");
    } else {
        generate_vma_bindings();
    }
}

#load "xml.jai";
#load "registry.jai";
#load "emitter.jai";
#load "vma_generator.jai";

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

