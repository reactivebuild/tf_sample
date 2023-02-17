load("@aspect_bazel_lib//lib:run_binary.bzl", "run_binary")

def tf_provider(name, src):
    native.filegroup(
        name = "file_%s" % name,
        srcs = [src],
    )
    native.sh_binary(
        name = "tf_init_builder_%s" % name,
        data = [
            ":file_%s" % name,
            "@terraform//:file",
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
        outs = [".terraform.lock.hcl"],
        execution_requirements = {
            "requires-network": "1",
        },
        args = [
            "$(location .terraform.lock.hcl)",
        ],
        out_dirs = [".terraform"],
    )
    native.sh_binary(
        name = "%s.save" % name,
        data = [
            ":%s" % name,
        ],
        args = [
            "$(locations %s)" % name,
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
