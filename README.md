# Nickel-K8S

This is an experimental project that aims to consolidate what typically scattered around in various tools into one system that can do the following;

- Create Configuration in one single language.
- Lint/Validate with the same language.
- Implement ServerSide validation when possible, K8 Schema is not strictly checked when using client side strategy aka json schema.
- Overlay/Augment the apps config to handle environmentations mutations in a unified without having to expose every little manifest option in an implicit schema.
- Add Policies to ensure certain Kube Manifest are using stricter schemas all the time and can be validated by both a validation/mutating server and the developer.

## Your first Release

This [https://github.com/tweag/nickel](Nickel) lib aims to simplify the processes of creating kubernetes resource while also not sacrificing the type safety and the correctness of the configurations. You can use the Umberella `Release` Contract that enforces all the kubernetes semantics for what represent a resource as well as automatically apply a type check on all your declared resources so that you don't misconfigure anything in the process. These checks include, schema type checks and validations that are typically evaluated with server side validation strategy, i.e. `kubectl apply -f file.yaml --dry-run=server`.

There is a lot to talk mention here but for starter let's show you the most basic nickel-k8s config that you can write and evaluated with `nickel export --format yaml --field package`.

```nickel
{
  Manifests = {
    deployment = {
      apiVersion = "apps/v1",
      kind = "Deployment",
      metadata.name = "my-test-deployment",
      spec = {
        selector = { matchLabels = { "test" = "test" } },
        template = {
          metadata.labels = { "test" = "test" },
          spec.containers = [
            {
              name = "test",
              image = "test",
            },
          ]
        }
      }
    }
  }
} | (import "types.ncl").Release
```

When you run this you should see an evaluation that gives you a back a Kuberenetes List Resource which represent an arbitrary list of k8 resource to deploy at one. This is what this lib utilize to organize your manifests. Internally there is an auto computed field package which we referenced in our previous call to give us the valid YAML file to apply using your favorite kubernetes client. For example, here is the full invocation you can use `nickel export --format yaml --field package | kubectl apply -f -`.

## Your first Env

Env and Release are the same thing, both can be extended, both can be constrained, both would yield the KubeList of many resources to generate the correct output. The only difference between the two is Constraints on the Env are always applied on all the Releases it contains.

For example if you had an Env with a Constraints that checks no Deployment or StatefulSet runs with a single replica, that would be applied to all the included applications.

```nickel
(import "types.ncl").CreateEnv { app = (import "app.ncl") }
```

This environment aggregates all the imported releases into a unified `Env` structure that allows you to inspect the full imported environment, this doesn't mean you need to deploy it using the Env. You are still able to target the releases to deploy if you prefer to do it that way.

## Anatomy of Nickel Program

Nickel Programs don't have structure, it is a config language and it is up to you to define a structure that make sense to you. In our case, we are structuring the following Contract/Type to be expected from all consumers of the system.

```nickel
{
    inputs | { .. },
    manifests | {_ : KubeResource },
    package | KubeList, # NOTE: this is implicitly computed for the user based on what is in manifest
    dns | { _ : String } # NOTE: Computed based on what is inside the manifest
}
```

The contract above is the release contract that we used in our #Your First Release section. `inputs` field is an open ended key value pairs that is meant to help the end user provide a small interface to modify their `manifests` in a non-intrusive way. Think for example image version in the deployment, and some label/annotations that differ based on the environment. This interface allow a user to define `inputs.version=0.0.1` and in the manifest field, this can be referenced to allow the user to easily override the image version. Maybe also override the standard `app.kubernetes.io/version` which should also point to the same version. A full example of this method can be seen in our example in `examples/otel.ncl`

This honestly is not my prefered method to override manifests can be useful for those who don't want to write a full record to override a specific path in the manifests.

Manifests on the hand is implement to be a dictionary of KubeResources, i.e. the records inside it should always have at least the following `apiVersion`, `kind` and `metadata.name`. Those are what identify a unique kubernetes resource. Anything manifest inside this dictionary is automatically validated against its contract which can be found in `lib/all.ncl`. CRDs right now are missing but those could easily be supplied by using `ExtensibleRelease` which is a method that takes as its first input a record of manfiests and the second input is the cluster domain.

`Dns` is a computed filed from the domain_names:ports based on any service kind that exists in manifests. This provide a nice way to reference these inside env to supply connection strings to inter connected services in the environment.

`Package` similar to dns, this is a computed field by the Release type. Users want to look at their manifests either in isolation or as a key value pair to easily patch them if necessary. This package basically generate the Kube List resource which holds an arbitrary list of resources inside its items field. This can be used along with kubectl to apply the generated configuration to your cluster.

Also as mentioned in #Write your First Env section, you could also manage various components as a stack/env that will all feed back to you

## Extensions

Extensibility is a big reason why I decided to create this system. Sometimes you work with OpenSource CRDs sometimes you want to work with internal CRDs in an Organaization. Regardless who owns the CRD, when you are managing resources using these APIs you want to validate them as well as ensuring you are using the correct version for them.

Both `Release` and `Env` have ways to supply your own APIs so the system will pick them up and use them for validation through an optional field called `Kinds`, the example below shows you how to provide your own schema for a CRD and have the system validate it.

**NOTE**: since `Kinds` are contract, you can evaluate the full module completely, instead you will need to target the computed package. `nickel export -f yaml myfile.ncl --field Package`. This is a side effect of allowing users to provide contracts.

```nickel
{
    Kinds = {
        MyCustomCRD = { # This field name is not used, just a way to better organize the CRDs
            apiVersion | String | force = "myApiVersion",
            kind | String | force = "myApiKind",
            metadata | {
                name | String,
                labels | { _ | String } | optional,
                annotatins | { _ | String } | optional,
            },
            spec | {
                number | Number
            },
        },
    },
    Manifests = {
        MyManifestsUsingMyCRD = {
            apiVersion = "myApiVersion",
            kind = "myApiKind",
            metadata.name = "test-name",
            spec = {number = 10,}
        }
    }
} | (import "kube.ncl").Release
```

## Merging vs User Defined inputs

If you used a system like Helm before, you are most likely familiar with the latter. Helm makes the user define their own inputs as an implicit schema. The types can either be validated inside of Helm itself using go templates or using a `schema.json` within the chart. There is no right or wrong approach, our system here allows both ways. Merge is more suitable when you have a change to be applied to all resources on a kind, a simple example is annotating all resources with a specific labels.

Inputs are more suitable when you want a more targeted approach to allow external users to modify one or two properties of the manifests in a simple way. A good example is the image version to be used in a pod/deployment. The following below shows you how to provide your own Inputs as a Nickel contract and how to consume it as well.

```nickel
{
  Inputs = { Version | String = "1.1.1" },
  Overlays = {
    Deployment = {
      apiVersion = "apps/v1",
      kind = "Deployment",
      spec.replicas = 3,
    },
  },
  Manifests = {
    MyManifestsUsingMyCRD = {
      apiVersion = "apps/v1",
      kind = "Deployment",
      metadata.name = "test-name",
      spec = {
        selector = {
          matchLabels = { app = "test", },
        },
        template = {
          metadata = { labels = { app = "test", } },
          spec = {
            containers = [{ name = "test", image = "myImage:" ++ Inputs.Version }],
          },
        },
      }
    }
  }
} | (import "kube.ncl").Release
```

## Migration

There is a simple migration scripts that can be used to convert a YAML stream to a Nickel object. The only requirement is to generate the computed yaml from your current system and push the output to a file called `all.yaml`. Here is an example of how to use this little nickel program with `helm template`.

```console
helm template ./my-chart-path > all.yaml
nickel eval migrate.ncl > converted.ncl
```

## TODO:

### Generating Contracts

All the contracts in the repo are hand crafted right now. This works as is but it doesn't capture the K8 Version used and expected by the calling consumer. There is [https://github.com/nickel-lang/json-schema-to-nickel](a Json Schema to Nickel Converter) that works. The issue is like all code generation tool you lose readability. A side goal of this project is to make it easier for non experts to quickly look up resource definitions from Nickel itself without an external resources/docs. With the way the code generation is done on the referenced project it is impossible to achieve that.

Also another point worth noting is that the contract modeled in this repo implement a server side validation, there are checks that Kubernetes only do at an API level, some are possible to capture within a single contract by itself like ensure Selector in a Deployment/StatefulSet can find the labels in the pod template. A JsonSchema Converter can never solve this since the schema doesn't enforce this right now and not even sure if such requirements can be expressed in a schema.json.

It should be possible generate the flat out contract as a basic contract for each kubernetes versions and it should also be possible to find the difference between the schemas. i.e. `NewSchema - OldSchema` should in theory yield the list of additions between two K8 versions, and the inverse should show us the removed manifests/fields between the two versions. Ideally we would want to capture when the first `apps/v1` schema got created, and then basically merge the contracts internally with their diffs. Either the contracts would add to fields in the case of new added behavior to the resource or it would create a blocking contract the disallow the usage of a removed field.

### Policy Agent

This project initially started as a policy agent, some of these are implemented right now through the `Constraints` in both `Release` and `Env`. This works fine right now as a client side approach for validating before pushing the resources to an API server.

It should be possible to create a Policy Agent that utilize the same bits `Contraints` model and apply those in a remote context such as `Validation Webhook` inside a cluster. This in theory would allow cluster operator to craft the policies and applying them inside the cluster while allow their users to apply the same policies.
