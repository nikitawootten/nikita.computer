---
title: How I manage my dotfiles with Ansible
date: 2022-05-29T18:09:33-04:00
tags: [ansible, dotfiles, git]
keywords: []
draft: no
---

_Update 1/12/2023: I have broken out my [dotfiles utility role](#the-dotfiles-role) into its own repository and I've listed it on Ansible Galaxy. [Check it out!](https://galaxy.ansible.com/nikitawootten/dotfiles)._

Configuration management is hard.
I first started to get serious about managing my dotfiles when I started college.
Before that, I'd treat the configuration of my machines as a [big ball of mud](https://en.wikipedia.org/wiki/Big_ball_of_mud).
You start off with a shiny new system, and as you install more and more software, you start to accumulate these _things_ that effect your workflow in mysterious ways.
Every time I'd find a weird workaround or neat alias to put in my `.bashrc`, I'd just leave it there to be forgotten the next time I started over with a _shiny new system_.
Worse yet, as I graduated to working with a laptop, a desktop, and even a server, my configuration became a _distributed_ big ball of mud.

Consolidating and codifying all of my configuration into a single source of truth has helped me immensely in several ways:

1. I do not get confused by changes between my machines.
   I can trust that the same aliases and utilities will be with me wherever I go.
2. I do not have to fear "starting over".
   If I accidentally wipe my laptop, or get a new machine, I can be back to working minutes after installing Linux.
3. I get all the benefits of revision control.
   If I'm tinkering with a configuration file and something breaks, I can tell exactly what I changed and when I changed it.

## My dotfiles journey

But first, a bit about the things I tried before settling on my current system.

### First attempt

My first attempt at managing my dotfiles involved a bash script that precariously symlinked files from my dotfiles repository:

```bash
...
# this could be pretty dangerous
cp -rfs $(pwd)/dotfiles/. ~/
...
```

This approach definitely beat having _nothing_ in place, but it still had problems.
My laptop and desktop machines at the time had vastly different configurations, including different software, desktop environments, and even different Linux distros.

I needed an approach that lended itself well to having multiple machines with some distinct configuration.

### Second attempt: grouping configuration files together and GNU Stow

[Stow](https://www.gnu.org/software/stow/) is a symlink manager that can be used pretty easily to manage dotfiles.
With Stow, I could group my configuration files for a given piece of software or a machine into its own directory, and apply it all at once.

Stow improved my dotfiles management workflow a lot.
Under this new workflow I had configuration specific to each machine, as well as specific configuration for different pieces of software.
I could have separate configuration for `i3` or `bspwm`, without polluting my environment on a given machine with both files if I wasn't planning on having it installed.

The problem, is that although my configuration files are managed with Stow, there is a lot more to a running system's state, such as:

1. What services are enabled and running?
2. What packages are installed?
3. What operating system is installed?

I needed a solution that manages all aspects of the state of a given machine.

## Introducing Ansible

[Ansible](https://www.ansible.com/) is a really powerful tool that can be used to automate all sorts of systems.

Ansible is built on a principle of idempotentcy, meaning if Ansible is run twice, the second run should not break the changes that were made the first time.
This is a great fit for dotfiles.
As my system evolves, I can commit a change on one system, distribute it to the other machines, and update their configuration without worrying about things breaking.

### Organizing capabilities into Ansible roles

Like I had with Stow, Ansible allows you to group together reusable pieces of configuration into _roles_.
Under the `roles/` directory, I could have specific configurations for a given capability I want that machine to have.

For example, I have a `Git` role that:

1. Installs Git
2. Configures Git

Altogether the role looks like this:

```yaml
# .dotfiles/roles/git/tasks/main.yaml
- name: Install Git
  ansible.builtin.package:
    name:
      - git
    state: present
  become: yes
- name: Configure Git
  ansible.builtin.shell: |
    git config --global user.name "Nikita Wootten"
    git config --global user.email <REDACTED>
    git config --global core.editor vim
    git config --global fetch.prune true
    git config --global pull.rebase false
```

_Note: I omitted some lines that I use to check if the Git configuration changed after being updated. The full configuration is [here](https://github.com/nikitawootten/.dotfiles/blob/master/roles/git/tasks/main.yaml)._

Roles can also depend on other roles, ensuring for example that the role that the role that sets up my Yubikey/GPG configuration is run before the role that sets up my SSH client configuration.

### The `dotfiles` role

Many of my roles depend on a small utility I wrote that mimics Stow with Ansible.

My custom `dotfiles` role (which you can find on [Ansible Galaxy](https://galaxy.ansible.com/nikitawootten/dotfiles)) scans a role for configuration files, and symlinks to resulting files to the appropriate location.

My ZSH role can then ensure all of my ZSH configuration has made it by invoking the `dotfiles` role:

```yaml
# .dotfiles/roles/zsh/tasks/main.yaml
---
- name: Symlink zsh dotfiles
  include_role:
    name: nikitawootten.dotfiles
```

### System playbooks

At the root of my dotfiles repository I have playbooks set up for each of my machines.
Each playbook includes the roles which define the capabilities I need for the machine.

My laptop's configuration looks like this:

```yaml
# .dotfiles/casper-magi.yaml
---
- name: Set up casper-magi
  hosts: localhost
  roles:
    - zsh
    - docker
    - ssh-client
    - git
    - yubikey
    - update-script
```

### The `update-script` role

The `update-script` role is another utility role I wrote which creates a script that can be run to update the machine.
This role prevents me from accidentally running the wrong playbook after setting up a machine.
On subsequent updates I only have to run `dotfiles-update`.

## Tying it all together

Check out my dotfiles [here](https://github.com/nikitawootten/.dotfiles).
