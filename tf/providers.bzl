load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

PluginInfo = provider(
    "Information about terraform provider",
    fields = {
        "plugin_file": "Provider file",
        "alias": "Location in registry",
    },
)

# Extract and copy terraform providers to the particularly structured plugin cache folder.
def _terraform_plugin_impl(ctx):
    out = ctx.actions.declare_file(ctx.attr.alias)
    ctx.actions.symlink(
        output = out,
        target_file = ctx.file.package,
    )
    return [
        PluginInfo(
            plugin_file = out,
            alias = ctx.attr.alias,
        ),
        DefaultInfo(
            files = depset([out]),
        ),
    ]

terraform_plugin = rule(
    implementation = _terraform_plugin_impl,
    attrs = {
        "package": attr.label(
            allow_single_file = True,
            mandatory = True,
        ),
        "alias": attr.string(
            mandatory = True,
        ),
    },
)

def register_terraform_plugin(name, export_file, sha256, urls, alias):
    http_archive(
        name = name,
        sha256 = sha256,
        urls = urls,
        build_file_content = """
load("@tf_sample//tf:providers.bzl", "terraform_plugin")
terraform_plugin(
    name = "%s",
    package = "%s",
    alias = "%s",
    visibility = ['//visibility:public'],
)
""" % (name, export_file, alias),
    )
