load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

load(":providers.bzl", "PluginInfo")

def get_terraform(version, platform, sha256):
    http_archive(
        name = "terraform_%s" % platform,
        build_file_content = "exports_files(['terraform'],visibility = ['//visibility:public'])",
        sha256 = sha256,
        urls = [
            "https://releases.hashicorp.com/terraform/{version}/terraform_{version}_{platform}.zip".format(
                version = version,
                platform = platform,
            ),
        ],
    )


def _tf_toolchain_impl(ctx):
    toolchain_info = platform_common.ToolchainInfo(
        name = ctx.label.name,
        executable = ctx.file.executable,
        plugins = ctx.attr.plugins,
    )
    return [toolchain_info]

tf_toolchain = rule(
    implementation = _tf_toolchain_impl,
    attrs = {
        "executable": attr.label(
            allow_single_file = True,
            executable = True,
            cfg = "exec",
        ),
        "plugins": attr.label_list(
            providers = [PluginInfo],
        ),
    },
    provides = [platform_common.ToolchainInfo],
)
