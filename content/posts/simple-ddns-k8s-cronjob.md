---
title: Simply managing Dynamic DNS in Kubernetes using the Cloudflare API
date: 2022-12-01T22:49:07-05:00
tags: [homelab, kubernetes, cloudflare, dns, tutorial]
keywords: []
draft: yes
---

For close to a decade now I've always run some sort of server at home, starting with a single Raspberry Pi Model B (still kicking today running [Pi-Hole](https://pi-hole.net/)!) and growing into a small collection of cheap decommissioned enterprise gear that I bought over the years.

<!-- Insert raspberry pi picture here -->

Dynamic DNS is the answer to the question "How do I know where my home servers live on the internet, and how do I connect to them?".

A lot of consumer (even ISP provided) routers can connect to services like NoIp or DynDNS without much hassle, and spinning up one of the many helper scripts or even builtin packages is trivial.
In this post I'd like to share with you how I set up a dynamic DNS client script using the Cloudflare API and a Kubernetes `CronJob` resource.

## Dynamic DNS

## Cloudflare API

## Kubernetes Resources

This script involves three simple Kubernetes resources:

- The `CronJob` detailing
- A `ConfigMap` resource containing the simple bash script executed by the `CronJob`.
