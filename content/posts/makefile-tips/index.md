---
title: "Tips for using Makefiles in your projects"
date: 2023-07-07T21:54:43-04:00
draft: false
tags: [makefile, nix, tips]
---

I have a secret: I adore Makefiles.
I'll admit, the syntax is a bit arcane, and if you don't know what you're doing you can create some really insidious bugs, but once things are set up you can really improve the developer experience on your projects likely without requiring developers to install any [additional tools](https://github.com/casey/just).
In this post I'd like to share some tips I've gathered for making your Makefiles more effective.

{{< alert "circle-info" >}}
This post assumes that you have surface knowledge of Makefiles.
If you'd like to learn more about Makefiles, check out the resources in the [conclusion](#conclusion).
{{< /alert >}}

## Tip: Automatically document your Makefiles

Picture this, you clone a random project off the internet.
The project's documentation instructs you to run `make help`, and to your delight you are greeted with a nicely formatted list of targets and their purpose.
This happened to me when playing around with a project called [`sbomnix`](https://github.com/tiiuae/sbomnix/tree/main) and since discovering it I've begun including a "self-documenting" `help` target to all of my projects:

```Makefile
.PHONY: help
help: ## Show this help message
	@grep --no-filename -E '^[a-zA-Z_-]+:.*?##.*$$' $(MAKEFILE_LIST) | awk 'BEGIN { \
	 FS = ":.*?## "; \
	 printf "\033[1m%-30s\033[0m %s\n", "TARGET", "DESCRIPTION" \
	} \
	{ printf "\033[32m%-30s\033[0m %s\n", $$1, $$2 }'
```

Now, running `make help` with a Makefile with this target present produces a nice list of targets and their description.
Any target annotated with `## <comment>` will show up (including the help target).
For example, here is the output of `make help` on the [Makefile used to build this very site](https://github.com/nikitawootten/nikitawootten.github.io/blob/main/Makefile):

{{<figure src="images/make-help.png" title="'make help' example output">}}

This snippet is modified from [this blog post](https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html).
I modified it to support targets within [Makefile includes](https://www.gnu.org/software/make/manual/html_node/Include.html) and to add the header.
[Other variations](https://docs.cloudposse.com/reference/best-practices/make-best-practices/#help-target) of this idea exist, choose one that suits you best, or make your own!

You might also want to consider making `help` your default goal:

```Makefile
# Run the help goal when the user runs `make`
.DEFAULT_GOAL: help
```

## Tip: Parallelize your Makefile

For larger projects with a lot of moving parts, you could potentially drastically speed up your build by running some targets in parallel.
Faster builds means better developer productivity, and also much better CI performance!
GitHub Actions gives you a [2-core CPU by default](https://docs.github.com/en/actions/using-github-hosted-runners/about-github-hosted-runners#supported-runners-and-hardware-resources), so there is performance you are potentially leaving on the table!

Thankfully, running Make operations in parallel is trivially easy, just add a `--jobs <n>` flag (where `n` is the limit to the number of jobs a Makefile can run at once, usually the number of cores your machine has).

```sh
# Run the specified target with up to <n> jobs in parallel
make <target> --jobs <n>
```

For more details, check out the ["Parallel Execution" section of the GNU Make Manual](https://www.gnu.org/software/make/manual/html_node/Parallel.html).

## Tip: Augment common Makefile operations with canned recipes

Canned recipes are useful when several targets have a lot of similarities.
Recipes can also improve the readability of a Makefile.

For more details, see the ["Canned Recipes" section of the GNU Make Manual](https://www.gnu.org/software/make/manual/html_node/Canned-Recipes.html).

### Example: Run commands within a Nix shell

Canned recipes are particularly useful for reducing the amount of repeated code, which can improve readability and reduce the possibility of mistakes.

For example, I house my [NixOS configurations in a repository](https://github.com/nikitawootten/infra) with a Makefile for common operations (updating, building, etc).
Some of these commands run in a special [Nix Shell](https://nixos.org/manual/nix/stable/command-ref/nix-shell.html) environment, allowing me to guarantee that the person running the commands has the correct dependencies.

I initially wrote my Makefile like this:

```Makefile
.PHONY: help test update switch-home build-home

test: ## Test flake outputs with "nix flake check"
	nix-shell shell.nix --command 'nix flake check'

update: ## Update "flake.lock"
	nix-shell shell.nix --command 'nix flake update'

switch-home: ## Switch local home-manager config
	nix-shell shell.nix --command 'home-manager switch --flake .'

build-home: ## Build local home-manager config
	nix-shell shell.nix --command 'home-manager build --flake .'

# ... more targets excluded for brevity
```

Using canned recipes I reduced it to this:

```Makefile
# Run command in nix-shell for maximum reproducibility (idiot [me] proofing)
define IN_NIXSHELL
	nix-shell shell.nix --command '$1'
endef

.PHONY: help test update switch-home build-home

test: ## Test flake outputs with "nix flake check"
	$(call IN_NIXSHELL,nix flake check)

update: ## Update "flake.lock"
	$(call IN_NIXSHELL,nix flake update)

switch-home: ## Switch local home-manager config
	$(call IN_NIXSHELL,home-manager switch --flake .)

build-home: ## Build local home-manager config
	$(call IN_NIXSHELL,home-manager build --flake .)
```

### Example: A simple For-Each recipe

The following canned recipe creates a simple "for-each" loop:

```Makefile
# $(call FOREACH,<item variable>,<items list>,<command>)
define FOREACH
	for $1 in $2; do {\
		$3 ;\
	} done
endef

friends:=bob alice

.PHONY: greet
greet:
	# Note that shell variables must be escaped with a double-$
	$(call FOREACH,friend,$(friends),echo "hello $$friend")
```

{{< alert >}}
This method does not play nicely with [parallelization](#tip-parallelize-your-makefile), since the loop runs serially.
In a lot of cases a better approach is to use [patterns](https://www.gnu.org/software/make/manual/html_node/Pattern-Intro.html) and [wildcard rules](https://earthly.dev/blog/using-makefile-wildcards/)
{{< /alert >}}

Running this makefile produces the output:

```sh
$ make
for friend in bob alice; do { echo "hello $friend" ; } done
hello bob
hello alice
```

### Example: Extending the For-Each recipe for multi-Makefile monorepos

Sometimes you'll have repositories with a lot of moving parts, including several project each complete with their own Makefiles.
Wouldn't it be great to have a single top-level Makefile that can run the `test` target for each project?
Fortunately extending [the For-Each recipe](#example-a-simple-for-each-recipe) to do so is trivial:

```Makefile
# $(call FOREACH_MAKE,<target>,<directories list>)
# Run a Makefile target for each directory, requiring each directory to
# 	have a given target
define FOREACH_MAKE
	@echo Running makefile target \'$1\' on all subdirectory makefiles
	@$(call FOREACH,dir,$2,$(MAKE) -C $$dir $1)
endef

# For all Makefiles matched by the wildcard, extract the directory
dirs:=$(dir $(wildcard ./*/Makefile))

.PHONY: test
test: ## Run all tests
	$(call FOREACH_MAKE,$@,$(dirs))
```

Running `make test` now runs each sub-directory's `test` target.

In some cases you might want to run a target on each Makefile, ignoring Makefiles that do not define one.
For example, say some sub-projects have a `clean` target, and others don't.
The following canned recipe allows you to run `make clean` only on directories that have a `clean` target:

```Makefile
# $(call FOREACH_MAKE_OPTIONAL,<target>,<directories list>)
# Run a Makefile target for each directory, skipping directories whose Makefile does not contain a rule
define FOREACH_MAKE_OPTIONAL
	@echo Running makefile target \'$1\' on all subdirectory makefiles that contain the rule
	@$(call FOREACH,dir,$2,$(MAKE) -C $$dir -n $1 &> /dev/null && $(MAKE) -C $$dir $1 || echo "Makefile target '$1' does not exist in "$$dir". Continuing...")
endef

dirs:=$(dir $(wildcard ./*/Makefile))

.PHONY: clean
clean: ## Remove any generated test or build artifacts
	$(call FOREACH_MAKE_OPTIONAL,$@,$(dirs))
```

## Tip: Use Makefile `include` for multi-Makefile projects

Using some of the tips you've gathered in this post, you may have accrued quite a bit of boilerplate now replicated in multiple Makefiles within the same repository.
Maybe now you've added [a "help" target to each Makefile](#tip-automatically-document-your-makefiles) and [one or two shared canned recipes](#tip-augment-common-makefile-operations-with-canned-recipes).
This is not very [DRY](https://en.wikipedia.org/wiki/Don%27t_repeat_yourself), we can do better!

Fortunately, [Makefile includes](https://www.gnu.org/software/make/manual/html_node/Include.html) make it simple to consolidate shared roles, recipes, and variables.

{{< alert "circle-info" >}}
Makefile inclusions are not "namespaced", so beware of clashing target and variable names.
{{< /alert >}}

```Makefile
# Include the contents of the Makefile ../shared/common.mk
include ../shared/common.mk
```

## Conclusion

If you have any Makefile tips that you'd like to share, feel free to leave a comment below or contact me.

If you'd like to learn more about Makefiles, check out some of the links below:

- [This really gentle introduction to Makefiles](https://endler.dev/2017/makefiles/) is great to send to team members looking to get started.
- [The GNU Make Manual](https://www.gnu.org/software/make/manual/html_node/) is an excellent reference. I find something interesting each time I read through it.
- [Self-Documented Makefile](https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html) is the excellent blog whose ["help" target I modified above](#tip-automatically-document-your-makefiles).
