"""Defines rules to create pyprotoc-based bazel rules."""

load("@rules_proto//proto:defs.bzl", "ProtoInfo")

def _get_proto_sources(context):
    proto_files = []

    for dependency in context.attr.deps:
        proto_files += [
            p
            for p in dependency[ProtoInfo].direct_sources
        ]

    return proto_files

def _declare_outputs(context):
    output_files = []

    for proto_file in context.files.srcs:
        output_files.append(
            context.actions.declare_directory(proto_file.basename.removesuffix('.proto') + '_generated')
        )

    return output_files

def _protoc_plugin_rule_implementation(context):
    proto_files = _get_proto_sources(context)
    output_files = _declare_outputs(context)

    output_directory = output_files[0].path
    if len(context.label.workspace_root) != 0:
        output_directory += "/" + context.label.workspace_root

    plugin_path = context.executable._plugin.path
    plugin_name = plugin_path.split("/")[-1]
    
    if not plugin_name.startswith("protoc-gen-"):
        fail("Plugin name %s does not start with protoc-gen-" % plugin_name)
    plugin_short_name = plugin_name.removeprefix("protoc-gen-")

    args = [
        "--plugin=%s=%s" % (plugin_name, plugin_path),
        "--%s_out" % plugin_short_name,
        # context.genfiles_dir.path,
        output_directory
    ]

    _virtual_imports = "/_virtual_imports/"
    for proto_file in proto_files:
        if len(proto_file.owner.workspace_root) == 0:
            # Handle case where `proto_file` is a local file.
            args += [
                "-I" + ".",
                proto_file.short_path,
            ]
        elif proto_file.path.startswith("external"):
            # Handle case where `proto_file` is from an external
            # repository (i.e., from 'git_repository()' or
            # 'http_archive()' or 'local_repository()').
            elements = proto_file.path.split("/")
            import_path = "/".join(elements[:2]) + "/"
            args += [
                "-I" + import_path,
                proto_file.path.replace(import_path, ""),
            ]
        elif _virtual_imports in proto_file.path:
            # Handle case where `proto_file` is a generated file file in
            # `_virtual_imports`.
            before, after = proto_file.path.split(_virtual_imports)
            import_path = before + _virtual_imports + after.split("/")[0] + "/"
            args += [
                "-I" + import_path,
                proto_file.path.replace(import_path, ""),
            ]
        else:
            fail(
                "Handling this type of (generated?) .proto file " +
                "was not forseen and is not implemented. " +
                "Please create an issue at " +
                "https://github.com/reboot-dev/pyprotoc-plugin/issues " +
                "with your proto file and we will have a look!",
            )

    context.actions.run_shell(
        outputs = output_files,
        inputs = proto_files,
        tools = [
            context.executable._protoc,
            context.executable._plugin,
        ],
        command = context.executable._protoc.path + " $@",
        arguments = args,
        use_default_shell_env = True,
    )

    return [DefaultInfo(
        files = depset(output_files),
    )]

def create_protoc_plugin_rule(plugin_label):
    return rule(
        attrs = {
            "deps": attr.label_list(
                mandatory = True,
                providers = [ProtoInfo],
            ),
            "srcs": attr.label_list(
                allow_files = True,
                mandatory = True,
            ),
            "_plugin": attr.label(
                cfg = "host",
                default = Label(plugin_label),
                # allow_single_file=True,
                executable = True,
            ),
            "_protoc": attr.label(
                cfg = "host",
                default = Label("@com_google_protobuf//:protoc"),
                executable = True,
                allow_single_file = True,
            ),
        },
        output_to_genfiles = True,
        implementation = _protoc_plugin_rule_implementation,
    )
