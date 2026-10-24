---
layout: default
title: Haikus
permalink: /haiku
---
<!-- List published haiku sources, independent of their public permalinks. -->
{%- assign published_pages = site.pages | where: "published", true | sort: "name" -%}
{%- assign markdown_extensions = site.markdown_ext | split: "," -%}
{%- capture haikus -%}
    {%- for haiku in published_pages -%}
        {%- assign source_prefix = haiku.path | slice: 0, 14 -%}
        {%- assign extension = haiku.path | split: "." | last | downcase -%}
        {%- assign suffix = haiku.path | split: "." | last | prepend: "." -%}
        {%- assign filename_length = haiku.name.size | minus: suffix.size -%}
        {%- assign filename = haiku.name | slice: 0, filename_length -%}
        {%- if source_prefix == "content/haiku/" and markdown_extensions contains extension -%}
            {%- unless haiku.literary_content == false or filename == "index" or filename == "_index" or filename == "random" or filename == "_random" -%}
                {%- assign title = haiku.title | default: "" | strip -%}
                <li><a href="{{ haiku.url | relative_url | escape }}">{{ title | default: filename | escape }}</a></li>
            {%- endunless -%}
        {%- endif -%}
    {%- endfor -%}
{%- endcapture %}

{::nomarkdown}
<div class="haiku-heading">
    <h1>Haikus</h1>
    <a class="icon-control" href="{{ '/haiku/random' | relative_url }}" aria-label="Read a random haiku" title="Read a random haiku">
        <span class="control-icon icon-arrowcircle icon-spin" aria-hidden="true"></span>
    </a>
</div>
{:/nomarkdown}

{% if haikus != "" %}
<ul>
{{ haikus }}
</ul>
{% else %}
No haikus have been published yet.
{% endif %}
