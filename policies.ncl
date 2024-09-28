# Collection of Standard policies for standard k8s operation
let lib = import "lib.ncl" in
{
  Container = {
    ImageAllowed
      | doc m%"
        Inspect containers in pod spec and make sure only images in the list registeries are used.
      "%
      | Array String -> Dyn
      = fun registries =>
        std.contract.custom (fun label value =>
          let image_in_registry = fun image =>
            std.array.any
              (fun e => std.string.is_match "^%{e}" image)
              registries
          in
          let errs =
            std.array.fold_right
              (fun e acc =>
                if image_in_registry e.image then
                  acc
                else
                  acc @ ["container: `%{e.name}`, image:`%{e.image}`"]
              )
              []
              value
          in
          errs
          |> match {
            a if std.array.length errs > 0 => 'Error { message = "One or more container are not using allowed registries", notes = errs, },
            _ => 'Ok value,
          }
        ),

    TagIsSemVer
      | doc "Ensure only semver images are deployed"
      =
        std.contract.custom (fun label value =>
          let pattern = "^\\d{1,2}\\.\\d{1,2}(\\.\\d{1,2})?$" in
          let tag_is_semver = fun image =>
            std.string.split ":" image
            |> std.array.last
            |> std.string.is_match pattern
          in
          let errs =
            std.array.fold_right
              (fun e acc =>
                if tag_is_semver e.image then
                  acc
                else
                  acc @ ["container: `%{e.name}`, image:`%{e.image}`"]
              )
              []
              value
          in

          if std.array.length errs == 0 then
            'Ok value
          else
            'Error { message = "One or more container is not using a semver", notes = errs }
        ),
  },

  Pod =
    let baseContainerSec =
      Array {
        ports
          | Array {
            hostPort | std.FailWith "Base security context disallow setting hostPort" | optional,
            ..
          }
          | optional,
        securityContext
          | {
            procMount | std.contract.Equal "Default" | optional,
            appArmorProfile # TODO: this need to take out for pod and container checks
              | {
                type
                  | lib.enum.StringOrEnum [| 'Default, 'Localhost |]
                  | optional,
                ..
              }
              | optional,
            capabilities
              | {
                add
                  | Array String
                  | Array (
                    lib.enum.ArrayEnum [
                      "AUDIT_WRITE",
                      "CHOWN",
                      "DAC_OVERRIDE",
                      "FOWNER",
                      "FSETID",
                      "KILL",
                      "MKNOD",
                      "NET_BIND_SERVICE",
                      "SETFCAP",
                      "SETGID",
                      "SETPCAP",
                      "SETUID",
                      "SYS_CHROOT",
                    ]
                  )
                  | optional,
                ..
              }
              | optional,
            ..
          }
          | optional,
        ..
      }
    in
    let harden = {
      spec
        | {
          volumes
            | Array {
              name | optional,
              configMap | optional,
              csi | optional,
              downward | optional,
              emptyDir | optional,
              persistentVolumeClaim | optional,
              projected | optional,
              secret | optional,
            }
            | optional,
          securityContext
            | {
              seccompProfile
                | {
                  type | lib.enum.StringOrEnum [| 'RuntimeDefault, 'Localhost |],
                  ..
                },
              runAsNonRoot | std.contract.Equal true,
              runAsUser
                | std.contract.from_validator (match {
                  0 => 'Error { message = "Can't run as root in hardened context" },
                  _ => 'Ok,
                }
                )
                | optional,
              ..
            },
          containers
            | Array {
              securityContext
                | {
                  seccompProfile
                    | {
                      type | lib.enum.StringOrEnum [| 'RuntimeDefault, 'Localhost |],
                      ..
                    },
                  allowPrivilegeEscalation | std.contract.Equal false,
                  runAsNonRoot | std.contract.Equal true,
                  capabilities
                    | {
                      drop | std.contract.Equal ["all"],
                      add | Array (lib.enum.StringOrEnum [| 'NET_BIND_SERVICE |]) | optional,
                      ..
                    },
                  ..
                },
              ..
            },
          ..
        },
      ..
    }
    in
    {
      # TODO: separate the policy from the overlay
      # separating the two provide value in the sense that we
      Base
        | doc m%"
        Baseline SecOp policy for pod policies.
        Ref here: https://kubernetes.io/docs/concepts/security/pod-security-standards/#baseline
        "%
        = {
          # TODO: adad these
          # metadata.annotations["container.apparmor.security.beta.kubernetes.io/*"]
          # Allowed Values
          # Undefined/nil
          # runtime/default
          # localhost/*
          spec
            | {
              securityContext
                | {
                  sysctls
                    | Array {
                      name
                        | Array (
                          lib.enum.StringOrEnums [|
                            '"kernel.shm_rmid_forced",
                            '"net.ipv4.ip_local_port_range",
                            '"net.ipv4.ip_unprivileged_port_start",
                            '"net.ipv4.tcp_syncookies",
                            '"net.ipv4.ping_group_range",
                            '"net.ipv4.ip_local_reserved_ports", # (since Kubernetes 1.27)
                            '"net.ipv4.tcp_keepalive_time", #(since Kubernetes 1.29)
                            '"net.ipv4.tcp_fin_timeout", #(since Kubernetes 1.29)
                            '"net.ipv4.tcp_keepalive_intvl", #(since Kubernetes 1.29)
                            '"net.ipv4.tcp_keepalive_probes", #(since Kubernetes 1.29)
                          |]
                        )
                        | optional,
                      ..
                    }
                    | optional,
                  appArmorProfile
                    | {
                      type | lib.enum.StringOrEnum [| 'RuntimeDefault, 'Localhost |] | optional,
                      ..
                    },
                  seccompProfile
                    | {
                      type | lib.enum.StringOrEnum [| 'RuntimeDefault, 'Localhost |] | optional,
                      ..
                    }
                    | optional,
                  seLinuxOptions
                    | {
                      type
                        | lib.enum.StringOrEnum [|
                          'container_t,
                          'container_init_t,
                          'container_kvm_t,
                          'container_engine_t # NOTE: 1.31.0+, how do we capture these in the future
                        |]
                        | optional,
                      user | std.FailWith "Base SecOp policy disallow setting linux user" | optional,
                      role | std.FailWith "Base SecOp policy disallow setting role" | optional,
                      ..
                    }
                    | optional,
                  ..
                }
                | optional,
              hostNetwork | std.contract.Equal false | optional,
              hostID | std.contract.Equal false | optional,
              hostIPC | std.contract.Equal false | optional,
              initContainers | baseContainerSec | optional,
              containers | baseContainerSec | optional,
              ephemeralContainers | baseContainerSec | optional,
              volumes | Array { hostPath | std.FailWith "Base security context disallow setting hostPath" | optional, .. } | optional,
              ..
            },
          ..
        },
      Restricted = Base | harden,
    },
  Deployment = {
    ImageAllowed
      | doc "Specialization of ContainerImageAllowed creating a Contract/Constract to be used in Release or Env"
      | Array String -> Dyn
      = fun registries =>
        {
          apiVersion = "apps/v1",
          kind = "Deployment",
          spec.template.spec.containers | Container.ImageAllowed registries,
          ..
        },
    RequestResourceSet
      | doc "Ensure all Deployment have CPU and Memory Configured"
      = {
        apiVersion = "apps/v1",
        kind = "Deployment",
        spec.template.spec.containers
          | Array {
            resources.requests
              | {
                # the module system will enforce the correct format, here we just want to remove the optionality
                cpu | Dyn,
                memory | Dyn,
                ..
              },
            ..
          },
        ..
      }
  },
}
