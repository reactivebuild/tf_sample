load(":providers.bzl", "PluginInfo")

def _find_plugin_by_name(plugin_name, plugins):
    matched = []
    for p in plugins:
        plugin_info = p[PluginInfo]
        plugin_file = plugin_info.plugin_file
        if plugin_file.basename == plugin_name:
            matched.append(plugin_info)
    if len(matched) == 0:
        fail("Could not find terraform plugin %s." % plugin_name)
    if len(matched) > 1:
        print(matched)
        fail("Multiple plugins with name %s are found." % plugin_name)

    # matched contains only one element.
    return matched[0]

TerraformModuleInfo = provider(
    "Info needed to run terraform actions: init, plan, apply",
    fields = {
        "module_marker": "File to mark module in the build tree",
        "output_marker": "File to mark terraform output folder",
        "backend_config_file": "Backend config file",
    },
)

def _tf_module_impl(ctx):
    out_marker = ctx.actions.declare_file(ctx.label.name + ".tf_module")
    ctx.actions.symlink(
        output = out_marker,
        target_file = ctx.file.marker,
    )

    plugins = ctx.toolchains["//tf:toolchain_type"].plugins
    providers = []
    for plugin_name in ctx.attr.plugins:
        plugin_info = _find_plugin_by_name(plugin_name, plugins)
        out = ctx.actions.declare_file(plugin_info.alias)
        ctx.actions.symlink(
            output = out,
            target_file = plugin_info.plugin_file,
        )
        providers.append(out)

    backend_config_file = None
    extra = []
    if ctx.attr.backend_config_file != None:
        backend_config_file = ctx.file.backend_config_file
        extra.append(backend_config_file)

    # Collect all files including transitive dependencies
    all_files = depset(
        ctx.files.srcs + providers + extra,
        transitive = [dep.files for dep in ctx.attr.deps],
    )

    return [
        TerraformModuleInfo(
            module_marker = ctx.file.marker,
            output_marker = out_marker,
            backend_config_file = backend_config_file,
        ),
        DefaultInfo(
            files = all_files,
        ),
    ]

tf_module = rule(
    implementation = _tf_module_impl,
    attrs = {
        "marker": attr.label(
            allow_single_file = True,
            mandatory = True,
        ),
        "deps": attr.label_list(
            providers = [TerraformModuleInfo],
        ),
        "srcs": attr.label_list(
            allow_files = [".tf"],
            mandatory = False,
        ),
        "plugins": attr.string_list(
            mandatory = False,
        ),
        "backend_config_file": attr.label(
            allow_single_file = True,
            mandatory = False,
        ),
    },
    toolchains = ["//tf:toolchain_type"],
)

# Generate terraform lock file in workspace.
def _tf_init_impl(ctx):
    # Let's collects module context.
    module_info = ctx.attr.module[TerraformModuleInfo]
    module_srcs = ctx.attr.module[DefaultInfo].files

    init_options = ""
    if module_info.backend_config_file != None:
        init_options = "-backend-config=" + module_info.backend_config_file.basename

    terraform = ctx.toolchains["//tf:toolchain_type"].executable

    out_file = ctx.actions.declare_file(ctx.label.name + ".bash")
    content = """set -eu
{terraform} -chdir={terraform_run_folder} init -upgrade \
    -plugin-dir=. -input=false -no-color {init_options}
rm -f $BUILD_WORKSPACE_DIRECTORY/{terraform_run_folder}/.terraform.lock.hcl
cp {terraform_run_folder}/.terraform.lock.hcl $BUILD_WORKSPACE_DIRECTORY/{terraform_run_folder}
chmod 644 $BUILD_WORKSPACE_DIRECTORY/{terraform_run_folder}/.terraform.lock.hcl
""".format(
        terraform = terraform.path,
        terraform_run_folder = module_info.module_marker.dirname,
        output_folder = module_info.output_marker.dirname,
        init_options = init_options,
    )
    ctx.actions.write(
        output = out_file,
        content = content,
        is_executable = True,
    )
    runfiles = ctx.runfiles(
        files = [terraform] + module_srcs.to_list(),
    )
    return [DefaultInfo(
        files = depset([out_file]),
        executable = out_file,
        runfiles = runfiles,
    )]

tf_init = rule(
    implementation = _tf_init_impl,
    attrs = {
        "lock": attr.label(
            allow_single_file = True,
            mandatory = True,
        ),
        "module": attr.label(
            providers = [TerraformModuleInfo],
            mandatory = True,
        ),
    },
    executable = True,
    toolchains = ["//tf:toolchain_type"],
)

def _tf_validate_test_impl(ctx):
    # Let's collects module context.
    module_info = ctx.attr.module[TerraformModuleInfo]
    module_srcs = ctx.attr.module[DefaultInfo].files
    terraform = ctx.toolchains["//tf:toolchain_type"].executable

    out_file = ctx.actions.declare_file(ctx.label.name + ".bash")
    content = """set -eu
# TF_LOG=debug
{terraform} -chdir={terraform_run_folder} init \
 -plugin-dir=. \
 -input=false -no-color -backend=false
{terraform} -chdir={terraform_run_folder} validate \
    -no-color
""".format(
        terraform = terraform.path,
        terraform_run_folder = module_info.module_marker.dirname,
        output_folder = module_info.output_marker.dirname,
    )
    ctx.actions.write(
        output = out_file,
        content = content,
        is_executable = True,
    )
    input = depset(
        [ctx.file.lock],
        transitive = [module_srcs],
    )
    runfiles = ctx.runfiles(
        files = [terraform] + input.to_list(),
    )
    return [DefaultInfo(
        files = depset([out_file]),
        executable = out_file,
        runfiles = runfiles,
    )]

tf_validate_test = rule(
    implementation = _tf_validate_test_impl,
    attrs = {
        "lock": attr.label(
            allow_single_file = True,
            mandatory = True,
        ),
        "module": attr.label(
            providers = [TerraformModuleInfo],
            mandatory = True,
        ),
    },
    test = True,
    toolchains = ["//tf:toolchain_type"],
)

# TODO A couple more options to try:
# export TF_PLUGIN_CACHE_DIR=
# -lock=false

PlanInfo = provider(
    "Info needed to run terraform apply",
    fields = {
        "plan_file": "File generated by terraform plan",
    },
)

def _tf_plan_impl(ctx):
    # Let's collects module context.
    module_info = ctx.attr.module[TerraformModuleInfo]
    module_srcs = ctx.attr.module[DefaultInfo].files

    init_options = ""
    if module_info.backend_config_file != None:
        init_options = "-backend-config=" + module_info.backend_config_file.basename

    # outputs
    plan = ctx.outputs.plan
    terraform_dir = ctx.outputs.terraform_dir
    outputs = [ctx.outputs.plan, terraform_dir]

    terraform = ctx.toolchains["//tf:toolchain_type"].executable

    command = """set -eu
# enable to debug local provider resolution export TF_LOG=debug
{terraform} -chdir={terraform_run_folder} init \
 -plugin-dir=$(pwd)/{output_folder} \
 -input=false -no-color {init_options}
{terraform} -chdir={terraform_run_folder} plan \
 -out=tfplan \
 -input=false
rm -rf $1
cp {terraform_run_folder}/tfplan $1
rm -rf $2
cp -rL {terraform_run_folder}/.terraform $2
""".format(
        terraform = terraform.path,
        terraform_run_folder = module_info.module_marker.dirname,
        output_folder = module_info.output_marker.dirname,
        init_options = init_options,
    )
    input = depset(
        [ctx.file.lock],
        transitive = [module_srcs],
    )
    ctx.actions.run_shell(
        mnemonic = "TerraformInit",
        inputs = input,
        tools = [terraform],
        command = command,
        arguments = [plan.path, terraform_dir.path],
        outputs = outputs,
    )

    return [
        PlanInfo(
            plan_file = plan,
        ),
        DefaultInfo(
            files = depset(
                outputs,
                transitive = [input],
            ),
        ),
    ]

tf_plan = rule(
    implementation = _tf_plan_impl,
    attrs = {
        "lock": attr.label(
            allow_single_file = True,
            mandatory = True,
        ),
        "module": attr.label(
            providers = [TerraformModuleInfo],
            mandatory = True,
        ),
    },
    outputs = {
        "plan": "tfplan",
        "terraform_dir": ".terraform",
    },
    toolchains = ["//tf:toolchain_type"],
)

def _tf_apply_plan_impl(ctx):
    out_file = ctx.actions.declare_file(ctx.label.name + ".bash")
    plan_info_dep = ctx.attr.plan[PlanInfo]
    plan_default_dep = ctx.attr.plan[DefaultInfo]

    terraform = ctx.toolchains["//tf:toolchain_type"].executable

    content = """set -eu
{terraform} -chdir={terraform_run_folder} apply \
 -input=false \
 tfplan
""".format(
        terraform = terraform.path,
        terraform_run_folder = ctx.label.package,
    )
    ctx.actions.write(
        output = out_file,
        content = content,
        is_executable = True,
    )
    runfiles = ctx.runfiles(
        files = [terraform] + plan_default_dep.files.to_list(),
    )
    return [DefaultInfo(
        files = depset([out_file]),
        executable = out_file,
        runfiles = runfiles,
    )]

# This one applies tfplan file generated by tf_plan rule
tf_apply_plan = rule(
    implementation = _tf_apply_plan_impl,
    attrs = {
        "plan": attr.label(
            mandatory = True,
            providers = [PlanInfo],
        ),
    },
    toolchains = ["//tf:toolchain_type"],
    executable = True,
)

def _tf_show_plan_impl(ctx):
    out_file = ctx.actions.declare_file(ctx.label.name + ".bash")
    plan_info_dep = ctx.attr.plan[PlanInfo]
    plan_default_dep = ctx.attr.plan[DefaultInfo]

    terraform = ctx.toolchains["//tf:toolchain_type"].executable

    content = """set -eu
{terraform} -chdir={terraform_run_folder} show {plan_file}
""".format(
        terraform = terraform.path,
        terraform_run_folder = ctx.label.package,
        plan_file = plan_info_dep.plan_file.basename,
    )
    ctx.actions.write(
        output = out_file,
        content = content,
        is_executable = True,
    )
    runfiles = ctx.runfiles(
        files = [terraform] + plan_default_dep.files.to_list(),
    )
    return [DefaultInfo(
        files = depset([out_file]),
        executable = out_file,
        runfiles = runfiles,
    )]

# Rule to show saved plan generated by tf_plan
tf_show_plan = rule(
    implementation = _tf_show_plan_impl,
    attrs = {
        "plan": attr.label(
            mandatory = True,
            providers = [PlanInfo],
        ),
    },
    toolchains = ["//tf:toolchain_type"],
    executable = True,
)

def _tf_apply_impl(ctx):
    # Let's collects module context.
    module_info = ctx.attr.module[TerraformModuleInfo]
    module_srcs = ctx.attr.module[DefaultInfo].files

    init_options = ""
    if module_info.backend_config_file != None:
        init_options = "-backend-config=" + module_info.backend_config_file.basename

    out_file = ctx.actions.declare_file(ctx.label.name + ".bash")
    terraform = ctx.toolchains["//tf:toolchain_type"].executable
    runfiles = ctx.runfiles(
        files = [terraform, ctx.file.lock] + module_srcs.to_list(),
    )

    apply_options = ""
    if ctx.attr.auto_approve:
        apply_options = apply_options + "-input=false -auto-approve"

    content = """set -eu
{terraform} -chdir={terraform_run_folder} init -plugin-dir=. -input=false {init_options}
{terraform} -chdir={terraform_run_folder} apply {apply_options}
""".format(
        terraform = terraform.path,
        terraform_run_folder = module_info.module_marker.dirname,
        output_folder = module_info.output_marker.dirname,
        apply_options = apply_options,
        init_options = init_options,
    )

    ctx.actions.write(
        output = out_file,
        content = content,
        is_executable = True,
    )
    return [DefaultInfo(
        files = depset([out_file]),
        executable = out_file,
        runfiles = runfiles,
    )]

# This one tries to call terraform apply without pre-generated plan file
tf_apply = rule(
    implementation = _tf_apply_impl,
    attrs = {
        "lock": attr.label(
            allow_single_file = True,
            mandatory = True,
        ),
        "module": attr.label(
            providers = [TerraformModuleInfo],
            mandatory = True,
        ),
        "auto_approve": attr.bool(
            default = False,
            mandatory = False,
        ),
    },
    toolchains = ["//tf:toolchain_type"],
    executable = True,
)
