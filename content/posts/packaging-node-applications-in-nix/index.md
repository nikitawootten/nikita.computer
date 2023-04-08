---
title: Packaging Node Applications in Nix using Yarn2Nix
date: 2023-04-08T09:15:40-05:00
tags: [nix, flakes, nodejs]
---

I recently rediscovered [Nix](https://nixos.org/), the confusingly named trifecta of language, package manager, and build system (oh, and an operating system but at least it has a slightly distinct name!), after getting increasingly frustrated with the state of configuration management.

Colleagues of mine frequently get burned with builds failing because of mismatched versions of some specific package on their machine, or some specific flag that should have been enabled in some configuration file that wasn't documented anywhere.
Worse, I get burned managing multiple personal and work machines that always have slight differences between them.
I've [tried to solve the latter before with Ansible](/posts/dotfiles/) but little differences still pile up and making my Ansible configuration work on different operating systems and distributions becomes its own chore.
This isn't a post about me solving these issues specifically, but Nix might be part of the solution which has me very excited.

This isn't the first time Nix has made me excited.
Around a year ago I found out about Nix, got super excited about it and even replaced my primary dev machine's operating system with NixOS only to be inundated with incomplete documentation, weird compromises (mostly caused by fundamental misunderstandings over what Nix **is**), and a community split over the adoption of [Flakes](https://nixos.wiki/wiki/Flakes).
I quickly got lost and my productivity plummeted while I tried to figure out how to even get VSCode working properly.
To put a long story short, I put the cart before the horse and fell for the hype before even realizing what the hype was about.

*This* time is different.
I've decided to take things slowly this time and really understand Nix before fully committing to it.
Part of that commitment will be documenting my journey and all the pain-points I come across.

In this post I'd like to share how I wrote my first overlay package in Nix, and some general tips I've gathered surrounding overlays and Flakes.

## The Application in question

The application in question is [OSCAL-deep-diff](https://github.com/usnistgov/oscal-deep-diff), a simple node application I built for work that compares large JSON documents.

*Disclaimer: Although I am the author and current maintainer of OSCAL-deep-diff, and while I work on this project as part of my job, this is not an official package endorsed by my organization.*

Packaging an application with Nix (especially with flakes) provides some really cool properties:
* You can reuse the package in other places easily (including other flakes).
* If packaged properly, you can run the package from anywhere Nix is installed using [`nix run`](https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-run.html).

## Packaging the application

Nix's build system is a complex patchwork of bash scripts and confusion as explained in [this incredibly helpful article by Julia Evans](https://jvns.ca/blog/2023/03/03/how-do-nix-builds-work-/).
Thankfully Nix provides a lot of helpers that make packaging really simple.
Unfortunately, figuring out *how* to use these abstractions is another matter, as not a lot of examples exist online and documentation is sparse.
I managed to get my package working by dissecting examples like [this](https://git.sr.ht/~bwolf/language-servers.nix/tree/master/item/vscode-langservers-extracted/default.nix).

Hopefully this writeup will serve as a good starting point for people trying to package similar applications built on top of the NPM ecosystem.

### It all starts with a `package.json`

OSCAL-deep-diff, like many Typescript-based CLI applications that leverage the NPM ecosystem, is just a bunch of Typescript code that links to other Javascript code that makes up its many dependencies:

{{<figure src="images/oscal_oscal_deep_diff_dependencies.svg" title="OSCAL-deep-diff's dependency graph" caption="OSCAL-deep-diff's dependency graph, generated via [npmgraph.js](https://npmgraph.js.org/?q=%40oscal%2Foscal-deep-diff)">}}

Lucky for me, all the "building" (compiling Typescript into Javascript) has already been done and all that my Nix derivation has to do is download all of the code and its dependencies, and stick it in the right place.

I'm having [Yarn](https://yarnpkg.com/) do all of the heavy lifting of downloading the built Javascript code and resolve all of its dependencies.

*NOTE: I chose to use Yarn instead of NPM here purely because it was the easiest for me to get working, your mileage may vary.*

In my package directory I can create a `package.json`:

```json
// packages/oscal-deep-diff/package.json
{
    "dependencies": {
        // My application is a single dependency
        // The version defined here will be the packaged application's version
        "@oscal/oscal-deep-diff": "1.0.0"
    },
    // None of this matters, but yarn gets really angry if you omit it and things will break
    "name": "oscal-deep-diff",
    "version": "1.0.0",
    "license": "NIST-PD-fallback"
}
```

Running `yarn` produces a lockfile containing the versions of all my package's dependencies, which can then be transformed into a Nix expression using [`yarn2nix`](https://nixos.org/manual/nixpkgs/stable/#yarn2nix).

In Nix this is as easy as running:
```bash
# Run the command `yarn2nix` in an environment with the package `yarn2nix`
$ nix-shell -p yarn2nix --command yarn2nix
```

I now have a `package.json`, `yarn.lock`, and `yarn.nix`, but how do I go about actually doing something useful with it?

### Creating the derivation

My Nix derivation needs to:
1. Download all Javascript dependencies (the `node_modules/` folder) to the output folder.
2. Create a script that invokes my application's starting point.

Step 1 is fairly easy using the [mkYarnModules](https://nixos.org/manual/nixpkgs/stable/#mkYarnModules) helper.
The following Nix expression produces a derivation that downloads all our dependencies to a `node_modules/` folder:
```Nix
# assuming the package name (pname), version, and nixpkgs as an input
pkgs.mkYarnModules {
  inherit pname version;
  packageJSON = ./package.json;
  yarnLock = ./yarn.lock;
  yarnNix = ./yarn.nix;
}
```

This fragment can be consumed in our final derivation (see the `deps` variable):

```Nix
# packages/oscal-deep-diff/default.nix
{ pkgs ? (import <nixpkgs> {}).pkgs }:
let
  pname = "oscal-deep-diff";
  # extract the version from package.json (ensuring these never get out of sync)
  version = (builtins.fromJSON (builtins.readFile ./package.json)).dependencies."@oscal/oscal-deep-diff";
  # grab our dependencies
  deps = pkgs.mkYarnModules {
    inherit pname version;
    packageJSON = ./package.json;
    yarnLock = ./yarn.lock;
    yarnNix = ./yarn.nix;
  };
in
pkgs.stdenv.mkDerivation {
  inherit pname version;

  # No build dependencies, all work has been done for you already by mkYarnModules
  nativeBuildInputs = with pkgs; [ ];
  buildInputs = with pkgs; [ ];

  # Grab the dependencies from the above mkYarnModules derivation
  configurePhase = ''
    mkdir -p $out/bin
    ln -s ${deps}/node_modules $out
  '';

  # Write a script to the output folder that invokes the entrypoint of the application
  installPhase = ''
    cat <<EOF > $out/bin/oscal-deep-diff
    #!${pkgs.nodejs}/bin/node
    require('$out/node_modules/@oscal/oscal-deep-diff/lib/cli/cli.js');
    EOF

    chmod a+x $out/bin/oscal-deep-diff
  '';

  # Skip the unpack step (mkDerivation will complain otherwise)  
  dontUnpack = true;
}
```

In the configure phase the derivation creates a symbolic link to the `node_modules/` folder created from the `deps` variable (the `mkYarnModules` call)/

In the install phase the derivation produces a script that invokes the entrypoint of the application.
Also notice that the [shebang](https://bash.cyberciti.biz/guide/Shebang) of the script points to `${pkgs.nodejs}/bin/node`, which is the version of node packaged by the `pkgs.nodejs` derivation.

### Testing the derivation

Building the derivation is as simple as running `nix-build`, which should produce an output folder `./result` containing our packaged script in `./result/bin` and all dependencies in `./result/node_modules`.

## Using the derivation from within a Flake

### Creating an overlay package

[Nix overlays](https://nixos.wiki/wiki/Overlays) are simple patterns that allow you to override your `nixpkgs` variable in order to add more packages or customize existing ones.
As of now I've only had to do the former, thankfully it's pretty simple to do!

I started with a overlay that looked like this:

```Nix
# packages/default.nix
final: prev: {
  # Import "default.nix" from the "oscal-deep-diff" directory
  oscal-deep-diff = prev.callPackage ./oscal-deep-diff { }
}
```

This module can now be passed in as an argument wherever your import `nixpkgs`.

### Sharing package versions with `flake.lock`

Currently when we build our derivation with `nix-build`, the version of `nixpkgs` used by modules like `mkYarnModules` and `mkDerivation` is defined by the system channel, not the version defined in the flake.
This inconsistency is subtle but easily avoidable.

What if we used Nix's [default argument operator](https://nixos.wiki/wiki/Overview_of_the_Nix_Language#Default_argument) to allow `pkgs` to be passed in when invoked through a flake, but if invoked through `nix-build` use the version of `nixpkgs` listed in the flake's lockfile?

It would look something like this:

```Nix
# packages/oscal-deep-diff/default.nix (fragment)
{ pkgs ? let
    # grab the lockfile and pull out the entry for `nixpkgs`
    lock = (builtins.fromJSON (builtins.readFile ../../flake.lock)).nodes.nixpkgs.locked;
    nixpkgs = fetchTarball {
      url = "https://github.com/nixos/nixpkgs/archive/${lock.rev}.tar.gz";
      sha256 = lock.narHash;
    };
  in
  import nixpkgs { }
, ...
}:
# ...
pkgs.stdenv.mkDerivation {}
# ...
```

I use this pattern everywhere.
It makes it very easy to create dev shells with [`mkShell`](https://nixos.org/manual/nixpkgs/stable/#sec-pkgs-mkShell) that share a Flake's environment even when Flakes aren't enabled on the system.

### Bonus: Wrapping common operations in a makefile

I want to make operations like regenerating the `yarn.nix` file as painless as possible.
I do not want to have to remember to install `yarn`, `yarn2nix`, and run a specific set of commands to update the package version.

Thankfully, Nix makes this really easy using a dev shell.

First, in my `oscal-deep-diff` package directory I create a `shell.nix` containing all my dependencies:

```Nix
# packages/oscal-deep-diff/shell.nix
{ pkgs ?
  let
    lock = (builtins.fromJSON (builtins.readFile ../../flake.lock)).nodes.nixpkgs.locked;
    nixpkgs = fetchTarball {
      url = "https://github.com/nixos/nixpkgs/archive/${lock.rev}.tar.gz";
      sha256 = lock.narHash;
    };
  in
  import nixpkgs { }
, ...
}:

pkgs.mkShell {
  packages = with pkgs; [
    nix
    yarn
    yarn2nix
  ];
}
```

I can enter this environment interactively with `nix-shell shell.nix`, but why do so when we can automate all operations using `make`:

```Makefile
# packages/oscal-deep-diff/Makefile
SHELL:=/usr/bin/env bash
IN_NIXSHELL:=nix-shell shell.nix --command

.PHONY: build genlock clean

build: genlock
	$(IN_NIXSHELL) 'nix-build'

genlock: yarn.lock yarn.nix

yarn.lock: package.json
	$(IN_NIXSHELL) 'yarn install --mode update-lockfile'
	rm -fr node_modules

yarn.nix: yarn.lock
	$(IN_NIXSHELL) 'yarn2nix > yarn.nix'

clean:
	rm -fr result yarn.*
```

Notice, that all targets are running *inside* the Nix shell environment defined earlier.
That means that if I want to update the package, all I have to do is run `make`, even if I'm not in an environment that has `yarn` installed.

## Conclusion

I hope this little retrospective helps you navigate Nix a little easier!
