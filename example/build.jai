#run {
    set_build_options_dc({ do_output = false });

    RootOptions := get_build_options();

    ImportPaths: [..]string;
    array_add(*ImportPaths, get_absolute_path(tprint("%../", #filepath),, temp));
    for Import: RootOptions.import_path {
        array_add(*ImportPaths, Import);
    }

    log("Include paths: %", ImportPaths);

    { // Vulkan test
        W := compiler_create_workspace("info");
        Options := get_build_options(W);

        copy_commonly_propagated_fields(RootOptions, *Options);
        Options.output_executable_name = "info";
        Options.import_path = ImportPaths;
        set_build_options(Options, W);

        add_build_file("info.jai", W);
    }

    { // VMA test
        W := compiler_create_workspace("vma");
        Options := get_build_options(W);

        copy_commonly_propagated_fields(RootOptions, *Options);
        Options.output_executable_name = "use_vma";
        Options.import_path = ImportPaths;
        set_build_options(Options, W);

        add_build_file("use_vma.jai", W);
    }
}

#import "Basic";
#import "Compiler";
#import "File";
#import "File_Utilities";

