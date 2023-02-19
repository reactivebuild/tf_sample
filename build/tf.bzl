load("@aspect_bazel_lib//lib:run_binary.bzl", "run_binary")

def tf_provider(name, src):
    lock_file = ".terraform.lock.hcl"

    # This part consumes lock and should not return it, otherwise it is cyclic dependencies problem
    native.sh_binary(
        name = "tf_init_builder_%s" % name,
        data = [
            src,
            "@terraform//:file",
            lock_file,
        ],
        srcs = ["//build:tf_init_builder.bash"],
        deps = [
            "@bazel_tools//tools/bash/runfiles",
        ],
    )
    run_binary(
        name = name,
        tool = ":tf_init_builder_%s" % name,
        mnemonic = "TerraformInit",
        outs = ["lock"],
        execution_requirements = {
            "requires-network": "1",
        },
        args = [
            "$(location lock)",
            native.package_name(),
        ],
        out_dirs = [".terraform"],
    )

    # Use <name>.init to respect terraform lock and prevent upgrades
    native.sh_binary(
        name = "%s.init" % name,
        data = [
            src,
            "@terraform//:file",
        ],
        args = [
            native.package_name(),
        ],
        srcs = ["//build:tf_init.bash"],
        deps = [
            "@bazel_tools//tools/bash/runfiles",
        ],
    )

def tf_module(name, srcs):
    native.filegroup(
        name = name,
        srcs = srcs,
    )

def tf_plan(name, provider, deps):
    native.sh_test(
        name = name,
        srcs = ["//build:tf_plan.bash"],
        data = deps + [
            provider,
            "@terraform//:file",
        ],
        args = [
            "$(location %s)" % provider,
        ],
        deps = [
            "@bazel_tools//tools/bash/runfiles",
        ],
    )
