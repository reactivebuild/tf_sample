load("@aspect_bazel_lib//lib:run_binary.bzl", "run_binary")

# Extract and copy terraform providers to the particularly structured plugin cache folder.
def tf_provider(name, alias, file):
    native.genrule(
        name = name,
        outs = [
            "cache/%s" % alias,
        ],
        cmd = "cp $(locations %s) $@" % file,
        srcs = [file],
        output_to_bindir = False,
    )

#def _tr_init_impl(ctx):
#    deps = depset(ctx.files.srcs)
#
#    #    deps = depset([ctx.files._terraform], transitive = [deps])
#    deps = depset(ctx.files._terraform, transitive = [deps])
#
#    # This is troubleshooting
#    lock_file = ctx.outputs.lock_file
#    ctx.actions.run_shell(
#        mnemonic = "TreeView",
#        inputs = deps,
#        outputs = [lock_file],
#        command = "echo $1",
#        arguments = [lock_file.path],
#    )
#
#    #    input = depset([x], transitive = [deps])
#    #    ctx.actions.run(
#    #        mnemonic = "TerraformInit",
#    #        executable = ctx.executable._terraform,
#    #        inputs = input,
#    #        arguments = [
#    #            "-chdir=" +
#    #            "-no-color",
#    #            "init",
#    #        ],
#    #        outputs = [lock_file],
#    #    )
#    return [DefaultInfo(files = depset([ctx.outputs.lock_file]))]
#
#tf_init = rule(
#    implementation = _tr_init_impl,
#    attrs = {
#        #        "lock": attr.label(
#        #            allow_single_file = True,
#        #        ),
#        "srcs": attr.label_list(
#            allow_files = [".tf"],
#            mandatory = True,
#        ),
#        "providers": attr.label_list(),
#        "_terraform": attr.label(
#            default = Label("@terraform//:file"),
#            allow_single_file = True,
#            executable = True,
#            cfg = "exec",
#        ),
#    },
#    outputs = {
#        "lock_file": ".terraform.lock.hcl",
#        #        "cache": ".terraform",
#    },
#    #    executable = True,
#)

def _tf_plan_impl(ctx):
    deps = depset(ctx.files.srcs)
    deps = depset([ctx.file.provider], transitive = [deps])
    deps = depset(ctx.files._terraform, transitive = [deps])
    deps = depset(ctx.files.providers, transitive = [deps])

    terraform = ctx.file._terraform
    provider = ctx.file.provider
    plan = ctx.outputs.plan

    lock_file = ctx.actions.declare_file(".terraform.lock.hcl", sibling = provider)

    # export TF_PLUGIN_CACHE_DIR=c &&
    # $TF -lock=false -input=false

    template = """
# export TF_LOG=debug
terraform -chdir={terraform_run_folder} init \
 -plugin-dir=$(pwd)/{output_folder}/cache \
 -input=false
terraform -chdir={terraform_run_folder} plan \
 -out=tfplan \
 -input=false
cp {terraform_run_folder}/.terraform.lock.hcl {output_folder}
cp {terraform_run_folder}/tfplan {output_folder}
tree -a
"""
    input = deps
    ctx.actions.run_shell(
        mnemonic = "TerraformInit",
        #        executable = terraform,
        inputs = input,
        command = template.format(
            output_folder = lock_file.dirname,
            terraform_run_folder = provider.dirname,
        ),
        outputs = [lock_file, plan],
    )

    return [DefaultInfo(files = depset([plan]))]

tf_plan = rule(
    implementation = _tf_plan_impl,
    attrs = {
        #        "lock": attr.label(
        #            default = ".terraform.lock.hcl",
        #            allow_single_file = True,
        #            mandatory = True,
        #        ),
        "provider": attr.label(
            default = "provider.tf",
            allow_single_file = True,
            mandatory = True,
        ),
        "srcs": attr.label_list(
            allow_files = [".tf"],
            mandatory = False,
        ),
        "providers": attr.label_list(
            allow_files = True,
            mandatory = False,
        ),
        "_terraform": attr.label(
            default = Label("@terraform//:terraform"),
            allow_single_file = True,
            executable = True,
            cfg = "exec",
        ),
    },
    outputs = {
        "plan": "tfplan",
    },
    #    executable = True,
)
