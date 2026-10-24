---
layout: default
title: ""
permalink: /story/random
published: true
literary_content: false
---
{%- assign published_pages = site.pages | where: "published", true -%}
{%- assign markdown_extensions = site.markdown_ext | split: "," -%}
{%- capture targets -%}
    {%- assign separator = "" -%}
    {%- for story in published_pages -%}
        {%- assign source_prefix = story.path | slice: 0, 14 -%}
        {%- assign extension = story.path | split: "." | last | downcase -%}
        {%- assign suffix = story.path | split: "." | last | prepend: "." -%}
        {%- assign filename_length = story.name.size | minus: suffix.size -%}
        {%- assign filename = story.name | slice: 0, filename_length -%}
        {%- unless story.literary_content == false or filename == "index" or filename == "_index" or filename == "random" or filename == "_random" -%}
            {%- if source_prefix == "content/story/" and markdown_extensions contains extension -%}
                {{- separator -}}{{- story.url | relative_url | jsonify | replace: "<", "\u003c" -}}
                {%- assign separator = "," -%}
            {%- endif -%}
        {%- endunless -%}
    {%- endfor -%}
{%- endcapture -%}
{::nomarkdown}
<p id="story-status" role="status" hidden></p>
<div id="story-content" data-kind="story"></div>
<button id="story-another" class="icon-control hero-control" type="button" aria-label="Get a new story" title="Get a new story" hidden>
    <span class="control-icon icon-arrowcircle icon-spin" aria-hidden="true"></span>
    <span>Get a new story</span>
</button>
<noscript><p>Enable JavaScript to read a random story on this page.</p></noscript>
<script id="story-targets" type="application/json">[{{ targets }}]</script>
<script src="{{ '/assets/js/random-haiku.js' | relative_url }}" defer></script>
{:/nomarkdown}
