const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const strip_debug_symbols = b.option(bool, "strip", "strip debugging symbols") orelse false;

    const toposort_mod = b.createModule(.{
        .root_source_file = b.path("src/toposort.zig"),
        .target = target,
        .optimize = optimize,
        .strip = strip_debug_symbols,
    });

    const cli_exe_mod = b.createModule(.{
        .root_source_file = b.path("src/toposort-cli.zig"),
        .target = target,
        .optimize = optimize,
        .strip = strip_debug_symbols,
    });
    cli_exe_mod.addImport("toposort", toposort_mod);

    const exe = b.addExecutable(.{
        .name = "toposort",
        .root_module = cli_exe_mod,
    });
    b.installArtifact(exe);

    // Not generating a static lib.
    // const lib = b.addLibrary(.{
    //     .linkage = .static,
    //     .name = "toposort",
    //     .root_module = toposort_mod,
    // });
    // b.installArtifact(lib);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const lib_unit_tests = b.addTest(.{
        .root_module = toposort_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_module = cli_exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);

}
