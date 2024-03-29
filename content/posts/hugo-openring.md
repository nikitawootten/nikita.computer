---
title: "Configuring my Congo themed Hugo blog to use Openring"
date: 2022-12-03T18:26:40-05:00
draft: false
tags: [hugo, meta, tutorial, makefile]
---

I really like Drew DeVault's [Openring](https://git.sr.ht/~sircmpwn/openring), an elegant utility that generates links to blogs that I follow under my posts (scroll to the end of this article, you may find something you like!).
In this post I'd like to walk you through how I set up Openring with my [Congo](https://jpanther.github.io/congo/) themed [Hugo](https://gohugo.io/) blog.

## Configuring Openring

Openring takes in a [Go templated HTML](https://pkg.go.dev/html/template) file (see the [official example](https://git.sr.ht/~sircmpwn/openring/tree/master/item/in.html)) as well as the feeds you want to display as arguments, and produces a filled out template as a result.
I first wrote a simple script that stuffed a file containing a list of RSS feeds into the correct arguments needed to run openring:

```bash
# openring.sh
#!/usr/bin/env bash

FEEDLIST=config/openring/feeds.txt
INPUT_TEMPLATE=config/openring/openring_template.html
OUTPUT=layouts/partials/openring.html

readarray -t FEEDS < $FEEDLIST

# populated below
OPENRING_ARGS=""

for FEED in "${FEEDS[@]}"
do
   OPENRING_ARGS="$OPENRING_ARGS -s $FEED"
done

openring $OPENRING_ARGS < $INPUT_TEMPLATE > $OUTPUT
```

This snippet reads a list of feeds and a template living in `config/openring/` and spits out a [Hugo partial template](https://gohugo.io/templates/partials/) containing the populated list of articles in the `layouts/partials` directory.

My Openring template is a tweaked version of the [example provided on the Openring repo](https://git.sr.ht/~sircmpwn/openring/tree/master/item/in.html).
My tweaks center around playing nicely with the [Congo](https://jpanther.github.io/congo/) theme which uses [Tailwind](https://tailwindcss.com/) for styling.

```html
<section class="webring">
    <h3>Articles from blogs I follow around the net:</h3>
    <section class="flex flex-wrap">
        {{range .Articles}}
        <div class="article flex flex-col m-1 p-1 bg-neutral-300 dark:bg-neutral-600">
            <h4 class="m-0">
                <a href="{{.Link}}" target="_blank" rel="noopener">{{.Title}}</a>
            </h4>
            <p class="summary">{{.Summary}}</p>
            <small>
                via <a href="{{.SourceLink}}">{{.SourceTitle}}</a>
            </small>
            <small>{{.Date | datef "January 2, 2006"}}</small>
        </div>
        {{end}}
    </section>
    <p class="text-sm text-neutral-500 dark:text-neutral-400 text-right">
        Generated by
        <a href="https://git.sr.ht/~sircmpwn/openring">openring</a>
    </p>
</section>
{{/* For the bits I couldn't figure out how to represent in Tailwind */}}
<style>
    .webring .article {
        flex: 1 1 0;
        min-width: 10rem;
    }
    .webring .summary {
        flex: 1 1 0;
        font-size: 0.8rem;
    }
</style>
```

## Loading in the generated Openring template

Depending on your theme, the process of injecting your Openring template will differ.
I'm using [Congo](https://jpanther.github.io/congo/), which [specifies](https://jpanther.github.io/congo/docs/partials/#head-and-footer) that a custom partial can be injected into the footer of all pages simply by naming it `layouts/partials/extend-footer.html`.
This isn't perfect, as I only want my Openring partial to be loaded on articles, excluding pages like my homepage, but luckily Hugo's template syntax makes this easy to fix by using the `.IsPage` field:

```html
{{/* layouts/partials/extend-footer.html */}}
{{/* Don't load the partial if it doesn't exist */}}
{{ if templates.Exists "partials/openring.html" }}
    {{ if .IsPage }}
        {{/* Only display at the bottom of articles */}}
        <div class="mt-6">
            {{ partial "openring.html" . }}
        </div>
    {{ end }}
{{ end }}
```

Now running the previously described script `openring.sh` followed by `hugo serve` should produce the results we're looking for!

## Tying it all together

Next, I made a simple makefile that pipelines `openring.sh` before running any relevant Hugo commands:

```Makefile
# Makefile

openring:
	./openring.sh

serve: openring
	hugo serve -p 8080

build: openring
	hugo

build-prod: openring
	hugo --minify
```

Now in my deployment instead of running `hugo --minify` I simply run `hugo build-prod`.

If you'd like to see the final state of my Hugo site after making these changes, check [here](https://github.com/nikitawootten/nikitawootten.github.io/) as a reference.
