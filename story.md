---
layout: default
title: Short Stories
permalink: /story
---
<!-- List only published story sources, independent of their public permalinks. -->
{%- assign published_pages = site.pages | where: "published", true | sort: "name" -%}
{%- capture stories -%}
    {%- for story in published_pages -%}
        {%- assign source_prefix = story.path | slice: 0, 14 -%}
        {%- assign extension = story.path | split: "." | last -%}
        {%- assign filename_length = story.name.size | minus: 3 -%}
        {%- assign filename = story.name | slice: 0, filename_length -%}
        {%- if source_prefix == "content/story/" and extension == "md" -%}
            {%- unless story.literary_content == false or filename == "index" or filename == "_index" or filename == "random" or filename == "_random" -%}
                {%- assign title = story.title | default: "" | strip -%}
                <li><a href="{{ story.url | relative_url | escape }}">{{ title | default: filename | escape }}</a></li>
            {%- endunless -%}
        {%- endif -%}
    {%- endfor -%}
{%- endcapture %}

# Short Stories

{% if stories != "" %}
<ul>
{{ stories }}
</ul>
{% else %}
No short stories have been published yet.
{% endif %}
