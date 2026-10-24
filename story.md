---
layout: default
title: Short Stories
permalink: /story
---
<!-- List story sources emitted by Jekyll, including drafts in unpublished previews. -->
{%- assign listed_pages = site.pages | sort: "name" -%}
{%- comment -%}Missing timestamps first; numeric date groups normalize strings/Times and retain name order for ties.{%- endcomment -%}
{%- assign undated_pages = listed_pages | where_exp: "item", "item.published_timestamp == nil" -%}
{%- assign dated_pages = listed_pages | where_exp: "item", "item.published_timestamp != nil" -%}
{%- assign dated_groups = dated_pages | group_by_exp: "item", "item.published_timestamp | date: '%s' | plus: 0" | sort: "name" | reverse -%}
{%- assign listed_pages = undated_pages -%}
{%- for group in dated_groups -%}
    {%- assign listed_pages = listed_pages | concat: group.items -%}
{%- endfor -%}
{%- capture stories -%}
    {%- for story in listed_pages -%}
        {%- assign source_prefix = story.path | slice: 0, 14 -%}
        {%- assign extension = story.path | split: "." | last -%}
        {%- assign filename_length = story.name.size | minus: 3 -%}
        {%- assign filename = story.name | slice: 0, filename_length -%}
        {%- if source_prefix == "content/story/" and extension == "md" -%}
            {%- unless story.literary_content == false or filename == "index" or filename == "_index" or filename == "random" or filename == "_random" -%}
                {%- assign title = story.title | default: "" | strip -%}
                <li>{% unless story.published == true %}[UNPUBLISHED] {% endunless %}<a href="{{ story.url | relative_url | escape }}">{{ title | default: filename | escape }}</a></li>
            {%- endunless -%}
        {%- endif -%}
    {%- endfor -%}
{%- endcapture %}

{::nomarkdown}
<div class="story-heading">
    <h1>Short Stories</h1>
    <a class="icon-control" href="{{ '/story/random' | relative_url }}" aria-label="Read a random story" title="Read a random story">
        <span class="control-icon icon-arrowcircle icon-spin" aria-hidden="true"></span>
    </a>
</div>
{:/nomarkdown}

{% if stories != "" %}
<ul>
{{ stories }}
</ul>
{% else %}
No short stories have been published yet.
{% endif %}
