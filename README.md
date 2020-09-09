# What is PodBuilder

PodBuilder is a complementary tool to [CocoaPods](https://github.com/CocoaPods/CocoaPods) that allows to prebuild pods into frameworks which can then be included into a project’s repo. Instead of committing pod’s source code you add its compiled counterpart. While there is a size penalty in doing so compilation times will decrease significantly because pod's source files no longer need to be recompiled _very often_ and there's also a lot less for SourceKit to index. Additionally frameworks contain all architecture so they’re ready to be used both on any device and simulator.

Depending on the size of the project and number of pods this can translate in a significant reduction of compilation times (for a large project we designed this tool for we saw a 50% faster compile times, but YMMV).

# Installation

Like CocoaPods PodBuilder is built with Ruby and will be installable with default version of Ruby available on macOS.

Unless you're using a Ruby version manager you should generally install using `sudo` as follows

    $ sudo gem install pod-builder

# Quick start

You can the initialize your project to use the tool using the `init` command

    $ cd path-to-your-repo;
    $ pod_builder init

 This will add a _PodBuilder_ folder which will contain all files needed and generated by the PodBuilder.

 To prebuild all dependencies run

    $ pod_builder build_all

 To prebuild just one or more specific dependencies run

    $ pod_builder build Pod1 Pod2

This will generate the pod frameworks which can be committed to your repo for a much faster compilation.

Should PodBuilder not work the way you expect you can get rid of it by running

    $ pod_builder deintegrate

Which will restore all changes that PodBUilder applied to the project (the PodBuilder folder and the changes to the Podfile).

# Usage

## Podfile

The workflow is very similar to the one you're used to with CocoaPods. The most significant difference is that PodBuilder relies on 3 Podfiles:

### 1. PodBuilder/Podfile (aka PodBuilder-Podfile)

This is your original Podfile and remains your **master Podfile** that you will update as needed. It is used by PodBuilder to determine which versions and dependencies need to be compiled when prebuilding.

### 2. Podfile (aka Application-Podfile)

Based on the one above but will replace precompiled frameworks with references to the local PodBuilder podspec. **It is autogenerated and shouldn't be manually changed**

### 3. PodBuilder/Podfile.restore (aka Restore-Podfile)

This acts as a sort of lockfile and reflects the current state of what is installed in the application, pinning pods to a particular tag or commit. This will be particularly useful until Swift reaches ABI stability, because when you check out an old revision of your code you won't be able to get your project running unless the Swift frameworks were compiled with a same version of Xcode you're currently using. This file is used internally by PodBuilder and shouldn't be manually changed. **It is autogenerated and shouldn't be manually changed**

## Commands

Podbuilder comes with a set of commands:

- `init`: initializes a project to use PodBuilder
- `deintegrate`: deintegrates PodBuilder's initialization
- `build`: prebuilts a specific pod declared in the PodBuilder-Podfile
- `build_all`: prebuilts all pods declared in the PodBuilder-Podfile
- `update`: prebuilts all pods that are out-of-sync with the Restore-Podfile
- `restore_all`: rebuilts all pods declared in the Restore-Podfile file
- `install_sources`: installs sources of pods to debug into prebuild frameworks
- `switch`: switch between prebuilt, development or standard pod in the Application-Podfile
- `clean`: removes unused prebuilt frameworks, dSYMs and source files added by install_sources
- `sync_podfile`: updates the Application-Podfile with all pods declared in the PodBuilder-Podfile file
- `info`: outputs json-formatted information reflecting the current status of prebuilt pods

Commands can be run from anywhere in your project's repo that is **required to be under git**. 

#### `init` command

This will sets up a project to use PodBuilder.

The following will happen:

- Create a _PodBuilder_ folder in your repo's root.
- Copy your original Podfile to _PodBuilder/Podfile_ (PodBuilder-Podfile)
- Add an initially empty _PodBuilder.json_ configuration file
- Modify the original Podfile (Application-Podfile) with some minor customizations
- Create/Update your Gemfile adding the `gem 'pod-builder'` entry

#### `deintegrate` command

This will revert `init`'s changes.

#### `build` command

Running `pod_builder build [pod name]` will precompile the pod that should be included in the PodBuilder-Podfile.

The following will happen:

- Create one or more (if there are dependencies) _.framework_ file/s under _PodBuilder/Prebuilt_ along with its corresponding _dSYM_ files (if applicable) 
- Update the Application-Podfile replacing the pod definition with the precompiled ones
- Update/create the Podfile.restore (Restore-Podfile)
- Update/create PodBuilder.podspec which is a local podspec for your prebuilt frameworks (more on this later)

By default PodBuilder will only rebuild pods when changes are detected in source code. This behaviour can be overridden by passing the `--force` flag.

#### `build_all` command

As `build` but will prebuild all pods defined in PodBuilder-Podfile.

#### `update` command

If you decide not to commit the _Prebuilt_ and _dSYM_ folders you can use this command to rebuild all those frameworks that are out-of-sync with the Restore-Podfile or that were built with a different version of the Swift compiler.

#### `restore_all` command

Will recompile all pods to the versions defined in the Restore-Podfile. You would typically use this when checking out an older revision of your project that might need to rebuild frameworks (e.g. You're using a different version of the Swift compiler) to the exact same version at the time of the commit.

#### `install_sources` command

When using PodBuilder you loose ability to directly access to the source code of a pod. To overcome this limitation you can use this command which downloads the pod's source code to _PodBuilder/Sources_ and with some [tricks](https://medium.com/@t.camin/debugging-prebuilt-frameworks-c9f52d42600b) restores the ability to use the debugger and step into the code of your prebuilt dependencies. This can be very helpful to catch the exact location of a crash when it occurs (showing something more useful than assembly code). It is however advisable to switch to the original pod when doing any advanced debugging during development of code that involves a pod.

#### `update_lldbinit` command

In some situations you may already have source code for your prebuilt frameworks, for example if your project is organized as a monorepo. In this case there is no need to use the `install_sources`, you can run this command passing the folder that contains the source code that you used to generate the prebuilt frameworks. 

This command will generate a custom lldinit file which will be stored in the _PodBuilder_ folder. Note that this file is added to the .gitignore since it contains absolute path information. Since Xcode 11.5 customly defined lldbinit can be selected in the Run tab in your scheme project ("LLDB Init File"). You should select the generated llbb file path or, if you're using project generation tools such as XcodeGen, you can set it to `${SRCROOT}/../PodBuilder/lldbinit`.

#### `switch` command

Once you prebuild a framework you can change the way it is integrated in your project.

Using the switch command you can choose to integrate it:

- standard. Reverts to the default one used by CocoaPods
- development. The _Development Pod_ used by CocoaPods
- prebuilt. Use the prebuilt pod

To support development pods you should specify the path(s) that contain the pods sources in _PodBuilder/PodBuilderDevPodsPaths.json_ as follows

```json
[
    "~/path_to_pods_1",
    "~/path_to_pods_2",
]
```

PodBuilder will automatically determine the proper path when switching a particular pod.

#### `clean` command

Deletes all unused files by PodBuilder, including .frameworks, .dSYMs and _Source_ repos.

#### `sync_podfile` command

Updates the Application with all pods declared in the PodBuilder-Podfile file. This can come in handy when adding a new pod to the PodBuilder-Podfile file you don't won't to prebuild straight away.

#### `info` command

Outputs json-formatted information reflecting the current status of prebuilt pods.

The output hash contains one key for each pod containing the following keys:

- `framework_path`: the expected path for the prebuilt framework
- `restore_info.version`: the expected version for the pod
- `restore_info.specs`: the expected list of specs for the pod
- `restore_info.is_static`: true if the expected pod produces a static framework
- `restore_info.swift_version`: the expected swift compiler version to prebuild pod
- `prebuilt_info`: some additional information about the the prebuilt framework, if it exists on disk
- `prebuilt_info.version`: the version of the pod that produced the current prebuilt framework
- `prebuilt_info.specs`: the specs of the pod that produced the current prebuilt framework (there might be multiple subspec that produce a single .framework)
- `prebuilt_info.is_static`: true if the current prebuilt framework is static
- `prebuilt_info.swift_version`: the swift compiler version that produced the current prebuilt framework

**Version format**

`restore_version` and `prebuilt_info.version` are hashes containing the following keys:
- `tag`: pods pinned to a specific tag of the CocoaPods official Specs
- `repo`, `hash`: pods pointing to an external repo + commit
- `repo`, `branch`: pods pointing to an external repo + branch
- `repo`, `tag`: pods pointing to an external repo + tag


# Configuration file

_PodBuilder.json_ allows some advanced customizations.

## Supported keys

#### `spec_overrides`

This hash allows to add/replace keys in a podspec specification. This can be useful to solve compilation issue or change compilation behaviour (e.g. compile framework statically by specifying `static_framework = true`) without having to fork the repo.

The key is the pod name, the value a hash with the keys of the podspec that need to be overridden.

As an example here we're setting `module_name` in Google's Advertising SDK:

```json
{
    "spec_overrides": {
        "Google-Mobile-Ads-SDK": {
            "module_name": "GoogleMobileAds"
        }
    }
}
```

### `skip_pods`

You may want to skip some pods to be prebuilt, you can do that as follows:

```json
{
    "skip_pods": [
        "PodA"
        ]
}
```


### `force_prebuild_pods`

You may want to force some pods to be prebuilt, this might be the case for prebuilt ones (pods with a single vendored .framework) which are dependencies of othere pods

```json
{
    "force_prebuild_pods": [
        "PodA"
        ]
}
```
  

#### `build_settings`

Xcode build settings to use. You can override the default values which are:

```json
{
    "build_settings": {
        "ENABLE_BITCODE": "NO",
        "GCC_OPTIMIZATION_LEVEL": "s",
        "SWIFT_OPTIMIZATION_LEVEL": "-Osize",
        "SWIFT_COMPILATION_MODE": "wholemodule"
    }
} 
```

#### `build_settings_overrides`

Like `build_settings` but per pod. Pod name can also refer to subspec.

```json
{
    "build_settings_overrides": {
        "PodA": {
            "SWIFT_OPTIMIZATION_LEVEL": "-O"
        },
        "PodB/Subspec": {
            "APPLICATION_EXTENSION_API_ONLY": "NO"
        }
    }
}
```

#### `build_system`

Specify which build system to use to compile frameworks. Either `Legacy` (standard build system) or `Latest` (new build system). Default value: `Legacy`.

#### `library_evolution_support`

Specify if Swift frameworks should be compiled with library evolution support (BUILD_LIBRARY_FOR_DISTRIBUTION).

#### `license_filename`

PodBuilder will create two license files a plist and a markdown file which contains the licenses of each pod specified in the PodBuilder-Podfile. Defailt value: `Pods-acknowledgements`(plist|md).

#### `project_name`

In complex project setups you may end up with the following error: "Found multiple xcodeproj/xcworkspaces...". If that is the case you can specify the name of your main project manually. For example if your application's project is "Example.xcworkspace" set the value for this key to `Example`.

#### `allow_building_development_pods`

Building development pods is by default not allowed unless you explicitly pass the allow_warnings flag. You can override this behavior by setting this key to true

#### `skip_licenses`

PodBuilder writes a plist and markdown license files of pods specified in the PodBuilder-Podfile. You can specify pods that should not be included, for example for private pods. 

```json
{
    "skip_licenses": ["Podname1", "Podname2"]
}
```

#### `subspecs_to_split`

Normally when multiple subspecs are specified in a target a single framework is produced. There are rare cases where you specify different subspecs in different targets: a typical case is subspec specifically designed for app extensions, where you want to use a subspec in the main app and another one in the app extension. 

**Warning**: This will work properly only for static frameworks (_static_framework = true_ specified in the podspec). See [issue](https://github.com/CocoaPods/CocoaPods/issues/5708) and [issue](https://github.com/CocoaPods/CocoaPods/issues/5643)

```json
{
    "subspecs_to_split": ["Podname1/Subspec1", "Podname1/Subspec2", "Podname2/Subspec1", "Podname2/Subspec1"]
}
```

#### `lfs_update_gitattributes` 

Adds a _.gitattributes_ to _PodBuilder/Prebuilt_ and _PodBuilder/dSYM_ to exclude large files. If `lfs_include_pods_folder` is true it will add a the same _.gitattributes_ to the application's _Pods_ folder as well.


#### `lfs_include_pods_folder`

See [`lfs_update_gitattributes`](#lfs_update_gitattributes).


#### `use_bundler`

If you use bundler to pin the version of CocoaPods in your project set this to true. Default false.

#### `build_for_apple_silicon`

If set to true built frameworks will include iPhone simulator slices for Apple silicon based hardware. Default false.


# Behind the scenes

PodBuilder leverages CocoaPods code and [cocoapods-rome plugin](https://github.com/CocoaPods/Prebuilt) to compile pods into frameworks. Every compiled framework will be boxed (by adding it as a `vendored_framework`) as a subspec of a local podspec. When needed additional settings will be automatically ported from the original podspec, like for example xcconfig settings.

# FAQ

### **I get an _'`PodWithError` does not specify a Swift version and none of the targets (`DummyTarget`)'_ when building**

The podspec of the Pod you're trying to build doesn't specify the swift_version which is required in recent versions of CocoaPods. Either contact the author/mantainer of the Pod asking it to fix the podspec or add a `spec_overrides` in _PodBuilder.json_.

```json
"spec_overrides": {
    "Google-Mobile-Ads-SDK": {
      "module_name": "GoogleMobileAds"
    },
    "PodWithError": {
      "swift_version": "5.0"
    }
}
```

### **After prebuilding my project no longer compiles**

A common problem you may encounter is with Objective-C imports. You should verify that you're properly importing all the headers of your pods with the angle bracket notation `#import <FrameworkName/HeaderFile.h>` instead of directly importing `#import "HeaderFile.h"`.

How to proceed in these cases?
1. Rebuild all frameworks with PodBuilder
2. Switch all your pods (use switch command or manually edit your Application-Podfile) back to the standard integration
3. One-by-one switch your pods back to prebuilt, verifying everytime that your Project still compiles.


### **Build failed with longish output to the stdout, what should I do next?**

Relaunch the build command passing `-d`, this won't delete the temporary _/tmp/pod_builder_ folder on failure. Open _/tmp/pod_builder/Pods/Pods.xcproject_, make the Pods-DummyTarget target visible by clicking on _Show_ under _Product->Scheme->Manage shemes..._ and build from within Xcode. This will help you understand what went wrong. Remeber to verify that you're building the _Release_ build configuration.


### **Do I need to commit compiled frameworks?**

No. If the size of compiled frameworks in your repo is a concern (and for whatever reason you can't use [Git-LFS](#git-lfs)) you can choose add the _Prebuilt_ and _dSYM_ folder to .gitignore and run `pod_builder update` to rebuild all frameworks that need to be recompiled.


### **I get an _'attempt to read non existent folder `/private/tmp/pod_builder/Pods/ podname'_ when building**

Please open an issue here. You may also add the name of the pod to the [`skip_pods`](#skip_pods) key in the configuration file and try rebuilding again.

# Git LFS

PodBuilder integrates with [Git Large File Storage](https://git-lfs.github.com) to move large files, like the prebuilt frameworks, out of your git repo. This allows to benefit from the compilation speed ups of the precompiled frameworks without impacting on your repo overall size.

When [`lfs_update_gitattributes = true`](#lfs_update_gitattributes) PodBuilder will automatically update the _.gitattributes_ with the files generated by PodBuilder when building pods.

# Try it out!

Under _Example_ there's a sample project with a Podfile adding [Alamofire](https://github.com/Alamofire/Alamofire) you can use to try PodBuilder out.

    $ pod_builder init
    $ pod_builder build_all

This will initialize the project to use PodBuilder and prebuild Alamofire, open the project in Xcode and compile.

# Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/Subito-it/PodBuilder.


# Caveats

Code isn't probably the cleanest I ever wrote but given the usefulness of the tool I decided to publish it nevertheless.


# Authors

[Tomas Camin](https://github.com/tcamin) ([@tomascamin](https://twitter.com/tomascamin))

# License

The gem is available under the Apache License, Version 2.0. See the LICENSE file for more info.
