load(":providers.bzl", "PluginInfo")

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
