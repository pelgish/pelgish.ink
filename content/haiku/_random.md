---
layout: null
title: Random haiku
permalink: /haiku/random
published: true
literary_content: false
---
{%- assign published_pages = site.pages | where: "published", true -%}
{%- assign markdown_extensions = site.markdown_ext | split: "," -%}
{%- capture targets -%}
    {%- assign separator = "" -%}
    {%- for haiku in published_pages -%}
        {%- assign source_prefix = haiku.path | slice: 0, 14 -%}
        {%- assign extension = haiku.path | split: "." | last | downcase -%}
        {%- unless haiku.literary_content == false -%}
            {%- if source_prefix == "content/haiku/" and markdown_extensions contains extension -%}
                {{- separator -}}{{- haiku.url | relative_url | jsonify | replace: "<", "\u003c" -}}
                {%- assign separator = "," -%}
            {%- endif -%}
        {%- endunless -%}
    {%- endfor -%}
{%- endcapture -%}
{::nomarkdown}
<!doctype html>
<html lang="{{ site.lang | escape }}">
<head>
    <meta charset="utf-8">
    <title>{{ page.title | escape }}</title>
    <link rel="canonical" href="{{ page.url | absolute_url | escape }}">
    <script id="haiku-targets" type="application/json">[{{ targets }}]</script>
    <script src="{{ '/assets/js/random-haiku.js' | relative_url }}" defer></script>
</head>
<body></body>
</html>
{:/nomarkdown}
